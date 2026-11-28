package main

import (
	"bufio"
	"bytes"
	"context"
	"crypto/sha256"
	"crypto/tls"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"time"
)

type session struct {
	env      environment
	options  globalOptions
	out      *output
	base     *url.URL
	hostport string
	client   *http.Client
	stream   *http.Client
	caps     capabilities
}

type capabilities struct {
	API          int      `json:"api"`
	Platform     string   `json:"platform"`
	CoreVersion  string   `json:"coreVersion"`
	Capabilities []string `json:"capabilities"`
}

var errRedirect = errors.New("redirect refused")

type fingerprintError struct {
	presented string
	expected  string
	source    string
}

func (e *fingerprintError) Error() string {
	return fmt.Sprintf("certificate %s does not match the expected %s", e.presented, e.expected)
}

func connect(env environment, options globalOptions, out *output) (*session, error) {
	base, err := url.Parse(options.url)
	if err != nil || base.Host == "" || (base.Scheme != "http" && base.Scheme != "https") {
		return nil, failure(exitUsage, "usage", "--url %q 不是 http:// 或 https:// 的控制器地址", options.url)
	}
	if base.User != nil {
		return nil, failure(exitUsage, "usage", "--url 里不要带用户名密码，密钥用 --secret")
	}
	base.Path, base.RawQuery, base.Fragment = "", "", ""
	hostport := controllerHostPort(base)

	dial := (&net.Dialer{Timeout: options.timeout}).DialContext
	if options.socket != "" {
		// Profile writes (rules append/remove, dns policy) are only accepted on
		// the App's App Group socket; a controller listener is read-only for
		// them. --socket dials that socket directly, for the same routes.
		socket := options.socket
		dial = func(ctx context.Context, _, _ string) (net.Conn, error) {
			return (&net.Dialer{Timeout: options.timeout}).DialContext(ctx, "unix", socket)
		}
		base = &url.URL{Scheme: "http", Host: "app-group"}
		hostport = socket
		options.url = "unix:" + socket
	}

	transport := &http.Transport{
		Proxy:               nil,
		DialContext:         dial,
		TLSHandshakeTimeout: options.timeout,
		ForceAttemptHTTP2:   true,
	}
	s := &session{env: env, options: options, out: out, base: base, hostport: hostport}
	expected, source := "", ""
	if base.Scheme == "https" {
		expected, source, err = s.expectedFingerprint(hostport)
		if err != nil {
			return nil, err
		}
		transport.TLSClientConfig = pinnedTLSConfig(expected, source)
	}
	noRedirect := func(*http.Request, []*http.Request) error { return errRedirect }
	s.client = &http.Client{Transport: transport, Timeout: options.timeout, CheckRedirect: noRedirect}
	s.stream = &http.Client{Transport: transport, CheckRedirect: noRedirect}
	if err := s.identify(); err != nil {
		return nil, err
	}
	if source == "option" {
		_ = rememberKnownHost(s.knownHostsPath(), hostport, expected)
	}
	return s, nil
}

func controllerHostPort(base *url.URL) string {
	if base.Port() != "" {
		return base.Host
	}
	if base.Scheme == "https" {
		return net.JoinHostPort(base.Hostname(), "443")
	}
	return net.JoinHostPort(base.Hostname(), "80")
}

func pinnedTLSConfig(expected, source string) *tls.Config {
	return &tls.Config{
		InsecureSkipVerify: true,
		MinVersion:         tls.VersionTLS12,
		VerifyConnection: func(state tls.ConnectionState) error {
			if len(state.PeerCertificates) == 0 {
				return &fingerprintError{expected: expected, source: source}
			}
			presented := certificateFingerprint(state.PeerCertificates[0].Raw)
			if presented != expected {
				return &fingerprintError{presented: presented, expected: expected, source: source}
			}
			return nil
		},
	}
}

func certificateFingerprint(der []byte) string {
	sum := sha256.Sum256(der)
	return formatFingerprint(sum[:])
}

func formatFingerprint(sum []byte) string {
	parts := make([]string, len(sum))
	for i, b := range sum {
		parts[i] = fmt.Sprintf("%02X", b)
	}
	return "sha256:" + strings.Join(parts, ":")
}

func normalizeFingerprint(text string) (string, bool) {
	text = strings.TrimSpace(text)
	text = strings.TrimPrefix(strings.TrimPrefix(text, "sha256:"), "SHA256:")
	digest, err := hex.DecodeString(strings.ReplaceAll(text, ":", ""))
	if err != nil || len(digest) != sha256.Size {
		return "", false
	}
	return formatFingerprint(digest), true
}

func (s *session) expectedFingerprint(hostport string) (string, string, error) {
	if s.options.fingerprint != "" {
		expected, ok := normalizeFingerprint(s.options.fingerprint)
		if !ok {
			return "", "", failure(exitUsage, "usage", "--fingerprint %q 不是 SHA-256 指纹（sha256:AB:CD:...）", s.options.fingerprint)
		}
		return expected, "option", nil
	}
	known, err := readKnownHosts(s.knownHostsPath())
	if err != nil {
		return "", "", failure(exitPeerError, "known-hosts", "读取 %s 失败: %v", s.knownHostsPath(), err)
	}
	if expected, ok := known[hostport]; ok {
		return expected, "known_hosts", nil
	}
	presented, err := probeFingerprint(hostport, s.options.timeout)
	if err != nil {
		return "", "", unreachable(err, s.options.url)
	}
	question := fmt.Sprintf("%s 的控制器出示的证书指纹是 %s。", hostport, presented)
	if !s.env.isTerminal || s.options.json {
		return "", "", &cliErrorWithFingerprint{
			cliError: cliError{exit: exitFingerprint, code: "fingerprint-unknown", message: question +
				"请与 Clash App「外部控制器」页显示的指纹核对，再用 --fingerprint（或 $CLASH_FINGERPRINT）指定；" +
				"或者在终端里运行一次，确认后会记住。未发送密钥。"},
			fingerprint: fingerprintError{presented: presented},
		}
	}
	fmt.Fprintf(s.env.stderr, "%s\n请与 Clash App「外部控制器」页显示的指纹核对。\n信任这个指纹吗？[y/N] ", question)
	answer, _ := bufio.NewReader(s.env.stdin).ReadString('\n')
	if !strings.EqualFold(strings.TrimSpace(answer), "y") && !strings.EqualFold(strings.TrimSpace(answer), "yes") {
		return "", "", &cliErrorWithFingerprint{
			cliError:    cliError{exit: exitFingerprint, code: "fingerprint-refused", message: "没有信任这个指纹，未发送任何内容"},
			fingerprint: fingerprintError{presented: presented},
		}
	}
	if err := appendKnownHost(s.knownHostsPath(), hostport, presented); err != nil {
		return "", "", failure(exitPeerError, "known-hosts", "把指纹记进 %s 失败: %v", s.knownHostsPath(), err)
	}
	fmt.Fprintf(s.env.stderr, "已记住 %s 的指纹 %s。\n", hostport, presented)
	return presented, "known_hosts", nil
}

type cliErrorWithFingerprint struct {
	cliError
	fingerprint fingerprintError
}

func (e *cliErrorWithFingerprint) Unwrap() []error {
	return []error{&e.cliError, &e.fingerprint}
}

func probeFingerprint(hostport string, timeout time.Duration) (string, error) {
	dialer := &net.Dialer{Timeout: timeout}
	conn, err := tls.DialWithDialer(dialer, "tcp", hostport, &tls.Config{InsecureSkipVerify: true, MinVersion: tls.VersionTLS12})
	if err != nil {
		return "", err
	}
	defer conn.Close()
	certificates := conn.ConnectionState().PeerCertificates
	if len(certificates) == 0 {
		return "", errors.New("对方没有出示证书")
	}
	return certificateFingerprint(certificates[0].Raw), nil
}

func (s *session) knownHostsPath() string {
	return filepath.Join(s.env.homeDir, ".config", "clash-cli", "known_hosts")
}

func readKnownHosts(path string) (map[string]string, error) {
	known := map[string]string{}
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return known, nil
	}
	if err != nil {
		return nil, err
	}
	for _, line := range strings.Split(string(data), "\n") {
		fields := strings.Fields(line)
		if len(fields) != 2 || strings.HasPrefix(fields[0], "#") {
			continue
		}
		if fingerprint, ok := normalizeFingerprint(fields[1]); ok {
			known[fields[0]] = fingerprint
		}
	}
	return known, nil
}

func rememberKnownHost(path, hostport, fingerprint string) error {
	known, err := readKnownHosts(path)
	if err != nil {
		return err
	}
	if known[hostport] == fingerprint {
		return nil
	}
	if _, err := forgetKnownHost(path, hostport); err != nil {
		return err
	}
	return appendKnownHost(path, hostport, fingerprint)
}

func forgetKnownHost(path, hostport string) (bool, error) {
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	var kept []string
	removed := false
	for _, line := range strings.Split(string(data), "\n") {
		if fields := strings.Fields(line); len(fields) == 2 && fields[0] == hostport {
			removed = true
			continue
		}
		if strings.TrimSpace(line) != "" {
			kept = append(kept, line)
		}
	}
	if !removed {
		return false, nil
	}
	text := strings.Join(kept, "\n")
	if text != "" {
		text += "\n"
	}
	return true, os.WriteFile(path, []byte(text), 0o600)
}

func appendKnownHost(path, hostport, fingerprint string) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	file, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o600)
	if err != nil {
		return err
	}
	defer file.Close()
	_, err = fmt.Fprintf(file, "%s %s\n", hostport, fingerprint)
	return err
}

func unreachable(err error, address string) error {
	return unreachableWith(err, address, "")
}

func unreachableWith(err error, address, hostport string) error {
	var mismatch *fingerprintError
	if errors.As(err, &mismatch) {
		message := fmt.Sprintf("控制器的证书指纹 %s 与指定的 %s 不符，未发送任何内容", mismatch.presented, mismatch.expected)
		code := "fingerprint-mismatch"
		if mismatch.source == "known_hosts" {
			code = "fingerprint-changed"
			forget := "clash-cli forget <地址:端口>"
			if hostport != "" {
				forget = "clash-cli forget " + hostport
			}
			message = fmt.Sprintf("对方指纹变了（可能在 App 里重新生成过证书）：现在是 %s，记住的是 %s。未发送任何内容。"+
				"在 App 里核对指纹后，重新复制 App 里的终端命令（带新指纹），或执行 %s 后再连一次",
				mismatch.presented, mismatch.expected, forget)
		}
		return &cliErrorWithFingerprint{cliError: cliError{exit: exitFingerprint, code: code, message: message}, fingerprint: *mismatch}
	}
	if errors.Is(err, errRedirect) {
		return failure(exitPeerError, "redirect", "控制器回了一个重定向，clash-cli 不跟随重定向")
	}
	return failure(exitUnreachable, "unreachable", "连接失败 %s（%v）——Clash App 的隧道是否开着？外部控制器是否开启？", address, rootCause(err))
}

func rootCause(err error) error {
	var urlError *url.Error
	if errors.As(err, &urlError) {
		return urlError.Err
	}
	return err
}

func (s *session) identify() error {
	response, err := s.request(context.Background(), s.client, http.MethodGet, "/clash/v1/capabilities", nil, nil)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	switch {
	case response.StatusCode == http.StatusNotFound:
		return failure(exitUnsupported, "not-clash-app",
			"%s 上的控制器不是 Clash App 的（没有 /clash/v1/capabilities），未做任何改动", s.options.url)
	case response.StatusCode == http.StatusUnauthorized || response.StatusCode == http.StatusForbidden:
		return failure(exitAuth, "unauthorized",
			"%s 拒绝了密钥：在 Clash App 的 更多 › 客户端设置 › 外部控制器 里复制密钥（CLASH_SECRET）；也可能这个端口上是别的程序的控制器", s.options.url)
	case response.StatusCode != http.StatusOK:
		return peerFailure(response)
	}
	if err := json.NewDecoder(io.LimitReader(response.Body, 1<<20)).Decode(&s.caps); err != nil || s.caps.API == 0 {
		return failure(exitUnsupported, "not-clash-app", "%s 上的控制器没有说明自己是 Clash App 的", s.options.url)
	}
	if s.caps.API > knownControllerAPI {
		return failure(exitUnsupported, "upgrade-cli",
			"对方的控制器 API 是 %d，这个 clash-cli 只认识到 %d：请更新 Clash App（clash-cli 随 App 内置）", s.caps.API, knownControllerAPI)
	}
	return nil
}

func (s *session) require(capability string) error {
	if slices.Contains(s.caps.Capabilities, capability) {
		return nil
	}
	return failure(exitUnsupported, "unsupported", "这个 Clash App（内核 %s）不支持 %s，请更新 App", s.caps.CoreVersion, capability)
}

func (s *session) request(ctx context.Context, client *http.Client, method, path string, query url.Values, body any) (*http.Response, error) {
	target := *s.base
	target.Path = path
	if query != nil {
		target.RawQuery = query.Encode()
	}
	var reader io.Reader
	if body != nil {
		data, err := json.Marshal(body)
		if err != nil {
			return nil, err
		}
		reader = bytes.NewReader(data)
	}
	request, err := http.NewRequestWithContext(ctx, method, target.String(), reader)
	if err != nil {
		return nil, failure(exitUsage, "usage", "%v", err)
	}
	if body != nil {
		request.Header.Set("Content-Type", "application/json")
	}
	if s.options.secret != "" {
		request.Header.Set("Authorization", "Bearer "+s.options.secret)
	}
	response, err := client.Do(request)
	if err != nil {
		return nil, unreachableWith(err, s.options.url, s.hostport)
	}
	return response, nil
}

func (s *session) call(method, path string, query url.Values, body any, into any) error {
	response, err := s.request(context.Background(), s.client, method, path, query, body)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode >= 400 {
		return peerFailure(response)
	}
	if into == nil || response.StatusCode == http.StatusNoContent {
		_, _ = io.Copy(io.Discard, response.Body)
		return nil
	}
	if err := json.NewDecoder(response.Body).Decode(into); err != nil {
		return failure(exitPeerError, "bad-response", "%s %s：回复不是 JSON: %v", method, path, err)
	}
	return nil
}

// appStoreLocalWritesOnly is the refusal marker the kernel sets when a write
// did not arrive on the App Group socket.
const appStoreLocalWritesOnly = "app-store-local-writes-only"

func peerFailure(response *http.Response) error {
	if response.Header.Get("X-Clash-Refusal") == appStoreLocalWritesOnly {
		hint := ""
		if socket := appGroupSocketHint(); socket != "" {
			hint = "（这台 Mac 上找到 " + socket + "）"
		}
		return failure(exitPeerError, "local-writes-only",
			"App 只在本机 App Group socket 上接受配置库的写入，控制器监听只读；用 --socket%s 或设 CLASH_SOCKET 再试", hint)
	}
	data, _ := io.ReadAll(io.LimitReader(response.Body, 64<<10))
	message := strings.TrimSpace(string(data))
	var upstream struct {
		Message string `json:"message"`
	}
	if json.Unmarshal(data, &upstream) == nil && upstream.Message != "" {
		message = upstream.Message
	}
	if message == "" {
		message = http.StatusText(response.StatusCode)
	}
	switch response.StatusCode {
	case http.StatusUnauthorized, http.StatusForbidden:
		return failure(exitAuth, "unauthorized", "控制器拒绝了密钥：在 Clash App 的 更多 › 客户端设置 › 外部控制器 里复制密钥（CLASH_SECRET）")
	}
	return failure(exitPeerError, fmt.Sprintf("http-%d", response.StatusCode), "%s (HTTP %d)", message, response.StatusCode)
}

func (s *session) follow(ctx context.Context, path string, query url.Values, each func(json.RawMessage) error) error {
	response, err := s.request(ctx, s.stream, http.MethodGet, path, query, nil)
	if err != nil {
		if ctx.Err() != nil {
			return nil
		}
		return err
	}
	defer response.Body.Close()
	if response.StatusCode >= 400 {
		return peerFailure(response)
	}
	scanner := bufio.NewScanner(response.Body)
	scanner.Buffer(make([]byte, 64<<10), 16<<20)
	for scanner.Scan() {
		line := bytes.TrimSpace(scanner.Bytes())
		if len(line) == 0 {
			continue
		}
		if err := each(json.RawMessage(slices.Clone(line))); err != nil {
			return err
		}
	}
	if ctx.Err() != nil {
		return nil
	}
	return s.streamEnded(scanner.Err())
}

func (s *session) streamEnded(cause error) error {
	response, err := s.request(context.Background(), s.client, http.MethodGet, "/clash/v1/capabilities", nil, nil)
	if err != nil {
		return failure(exitUnreachable, "stream-ended", "控制器关闭了这条流，现在也连不上了（隧道可能已停止，或外部控制器的设置改了）")
	}
	_, _ = io.Copy(io.Discard, response.Body)
	_ = response.Body.Close()
	if response.StatusCode == http.StatusUnauthorized || response.StatusCode == http.StatusForbidden {
		return failure(exitAuth, "secret-changed", "密钥已更换，用旧密钥打开的流已断开：在 Clash App 的 更多 › 客户端设置 › 外部控制器 里复制新密钥")
	}
	if cause != nil {
		return failure(exitUnreachable, "stream-ended", "控制器关闭了这条流：%v", cause)
	}
	return failure(exitUnreachable, "stream-ended", "控制器关闭了这条流")
}

// appGroupSocketHint looks for the App's control socket so a refused write can
// name it. The identifier differs between builds, so the directory is globbed
// instead of hardcoded.
func appGroupSocketHint() string {
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	matches, _ := filepath.Glob(filepath.Join(home, "Library", "Group Containers", "*", "working", "clash.sock"))
	for _, match := range matches {
		if _, err := os.Stat(match); err == nil {
			return match
		}
	}
	return ""
}
