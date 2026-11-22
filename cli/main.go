package main

import (
	"fmt"
	"io"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"
)

var cliVersion = "1.0.0"

const knownControllerAPI = 1

const (
	exitOK          = 0
	exitPeerError   = 1
	exitUsage       = 2
	exitUnreachable = 3
	exitAuth        = 4
	exitUnsupported = 5
	exitFingerprint = 6
)

type cliError struct {
	exit    int
	code    string
	message string
}

func (e *cliError) Error() string { return e.message }

func failure(exit int, code, format string, args ...any) *cliError {
	return &cliError{exit: exit, code: code, message: fmt.Sprintf(format, args...)}
}

type environment struct {
	args       []string
	getenv     func(string) string
	stdin      io.Reader
	stdout     io.Writer
	stderr     io.Writer
	isTerminal bool
	color      bool
	homeDir    string
}

func main() {
	home, _ := os.UserHomeDir()
	env := environment{
		args: os.Args[1:], getenv: os.Getenv, stdin: os.Stdin, stdout: os.Stdout, stderr: os.Stderr,
		isTerminal: isTerminal(os.Stdin), color: isTerminal(os.Stdout), homeDir: home,
	}
	os.Exit(run(env))
}

type globalOptions struct {
	url         string
	secret      string
	secretStdin bool
	fingerprint string
	socket      string
	json        bool
	timeout     time.Duration
}

func run(env environment) int {
	options := globalOptions{
		url:         firstNonEmpty(env.getenv("CLASH_API"), "http://127.0.0.1:9090"),
		secret:      env.getenv("CLASH_SECRET"),
		fingerprint: env.getenv("CLASH_FINGERPRINT"),
		socket:      env.getenv("CLASH_SOCKET"),
		timeout:     8 * time.Second,
	}
	var timeoutErr error
	if text := env.getenv("CLASH_TIMEOUT"); text != "" {
		options.timeout, timeoutErr = parseTimeout(text)
	}
	parsed, err := parseArguments(env.args, &options)
	out := &output{json: options.json, stdout: env.stdout, stderr: env.stderr, color: env.color && !options.json}
	if err == nil && timeoutErr != nil {
		err = failure(exitUsage, "usage", "CLASH_TIMEOUT: %v", timeoutErr)
	}
	if err != nil {
		return out.fail(err)
	}
	if len(parsed.positional) == 0 || parsed.positional[0] == "help" || parsed.flags["help"] != "" {
		fmt.Fprint(env.stdout, usageText)
		if len(parsed.positional) == 0 && parsed.flags["help"] == "" {
			return exitUsage
		}
		return exitOK
	}
	if options.secretStdin {
		line, err := readFirstLine(env.stdin)
		if err != nil {
			return out.fail(failure(exitUsage, "usage", "--secret-stdin: %v", err))
		}
		options.secret = line
		env.isTerminal = false
	}
	command := parsed.positional[0]
	switch command {
	case "reload":
		return out.fail(failure(exitUnsupported, "managed-by-app", "配置由 Clash App 管理，请在 App 里更新或切换配置（clash-cli 不重载配置）"))
	case "version":
		return runVersion(env, options, out)
	case "skill":
		if options.json {
			return out.succeed(map[string]any{"skill": skillText}, nil)
		}
		fmt.Fprint(env.stdout, skillText)
		return exitOK
	case "forget":
		return runForget(env, out, parsed)
	case "check":
		return runCheck(env, out, parsed)
	}
	handler, ok := commands[command]
	if !ok {
		return out.fail(failure(exitUsage, "usage", "未知命令: %s（clash-cli help 查看可用命令）", command))
	}
	session, err := connect(env, options, out)
	if err != nil {
		return out.fail(err)
	}
	if err := handler(session, parsed); err != nil {
		return out.fail(err)
	}
	return exitOK
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if value != "" {
			return value
		}
	}
	return ""
}

func readFirstLine(reader io.Reader) (string, error) {
	var builder strings.Builder
	buffer := make([]byte, 1)
	for {
		n, err := reader.Read(buffer)
		if n == 1 {
			if buffer[0] == '\n' {
				break
			}
			builder.WriteByte(buffer[0])
		}
		if err == io.EOF {
			break
		}
		if err != nil {
			return "", err
		}
	}
	line := strings.TrimRight(builder.String(), "\r")
	if line == "" {
		return "", fmt.Errorf("the first line of standard input is empty")
	}
	return line, nil
}

func runForget(env environment, out *output, parsed parsedArguments) int {
	if len(parsed.positional) != 2 {
		return out.fail(usage("clash-cli forget <地址:端口>（例如 192.168.1.20:9443，或设备的 https:// 地址）"))
	}
	target := parsed.positional[1]
	if !strings.Contains(target, "://") {
		target = "https://" + target
	}
	parsed2, err := url.Parse(target)
	if err != nil || parsed2.Hostname() == "" {
		return out.fail(usage("clash-cli forget <地址:端口>"))
	}
	hostport := controllerHostPort(parsed2)
	path := filepath.Join(env.homeDir, ".config", "clash-cli", "known_hosts")
	removed, err := forgetKnownHost(path, hostport)
	if err != nil {
		return out.fail(failure(exitPeerError, "known-hosts", "忘记 %s 的指纹失败: %v", hostport, err))
	}
	return out.succeed(map[string]any{"forgotten": removed, "host": hostport}, func() {
		if removed {
			fmt.Fprintf(env.stdout, "✓ 已忘记 %s 的证书指纹，下次连接会重新确认\n", hostport)
		} else {
			fmt.Fprintf(env.stdout, "没有记住 %s 的指纹，不用忘记\n", hostport)
		}
	})
}

func runVersion(env environment, options globalOptions, out *output) int {
	data := map[string]any{"cli": cliVersion}
	core := ""
	if session, err := connect(env, options, out); err == nil {
		var version map[string]any
		if err := session.call("GET", "/version", nil, nil, &version); err == nil {
			data["core"], data["platform"] = version, session.caps.Platform
			core = fmt.Sprint(version["version"])
		}
	}
	return out.succeed(data, func() {
		fmt.Fprintf(env.stdout, "clash-cli %s（Clash App 内置）\n", cliVersion)
		if core != "" {
			fmt.Fprintf(env.stdout, "内核 %s\n", core)
		} else {
			fmt.Fprintf(env.stdout, "内核：没有连上控制器（%s）\n", options.url)
		}
	})
}

const usageText = `clash-cli —— Clash App 内置的命令行工具

从 Mac 终端查询和控制 Clash App 的内核：本机（外部控制器「仅本机」档），
或局域网里的 iPhone / iPad / Apple TV（「局域网」档，TLS + 证书指纹）。
只连 Clash App 的控制器。

用法: clash-cli [全局选项] <命令> [参数...]

全局选项（也可用环境变量）:
  -u, --url URL          控制器地址（$CLASH_API，默认 http://127.0.0.1:9090）；
                         设备的局域网档是 https://<设备 IP>:<端口>
  --secret 密钥           控制器密钥（$CLASH_SECRET；在 App 的 更多 › 客户端设置 › 外部控制器 里复制）
  --secret-stdin         从标准输入第一行读密钥
  --fingerprint 指纹      期望的证书指纹 sha256:AB:CD:...（$CLASH_FINGERPRINT）；不给时首次连接会问一次并记住
  --socket 路径          直连本机 App Group socket（$CLASH_SOCKET）；配置库的写入只在这个 socket 上被接受
  --json                 每条命令在 stdout 输出一个 JSON：{"cli":1,"ok":...}
  --timeout 时长          单次请求超时（$CLASH_TIMEOUT，默认 8 秒；不作用于流）

查看（只读）:
  status                         版本、模式、内存、流量、连接数、各策略组当前选择
  proxies [组]                   列策略组与节点；带组名看该组成员
  proxy get <组>                 该组当前选择与可选成员
  connections [N] [-f]           活跃连接（host → 策略链 → 命中规则 → 上下行），默认前 20；-f 持续
  rules [N]                      规则列表，默认前 10（0 = 全部）
  rule match <域名|IP|URL> [port=N] [network=tcp|udp] [src=IP] [process=名称] [--resolve]
                                 这条连接会命中哪条规则、走哪条链（不建连接；默认不解析 DNS）
  configs                        当前运行配置
  traffic [秒] [-f]              实时流量；给秒数读这么多秒
  logs [秒] [level] [-f]         日志（debug|info|warning|error）
  dns query <域名> [type]         走内核 DNS 查询
  dns explain <域名> [type]       解释这次查询会用哪组 DNS
  provider list                  节点集与规则集
  test <节点> [url] [timeout_ms]  测一个节点的延迟（不改任何选择）
  grouptest <组> [url] [timeout_ms]
                                 逐个测组内成员（不改任何选择）
  version | skill                版本 | 给 AI 代理的 SKILL.md
  forget <地址:端口>               忘记记住的证书指纹（设备重新生成证书后用），下次连接重新确认

改动（先确认目标存在）:
  proxy set <组> <节点>           切换节点（节点名逐字一致，含 emoji 与空格）
  mode [rule|global|direct]      查看或切换出站模式
  group unfix <组>               解除组的固定选择
  group test <组> [url] [timeout_ms]
                                 用组接口测速；对 URLTest/Fallback 组会先解除固定
  provider update proxy|rule <名称>
                                 让隧道向服务器检查这个集合一次，按结果报
  provider test <节点集>          对节点集做一次健康检查
  conn close <id|all>            关闭一条或全部连接（all 会打断下载与 SSH）
  flush fakeip|dns               清空 fake-ip 池或 DNS 缓存

配置库（改 App 里存的那份配置，不动现在的连接，下次连接生效）:
  profiles                       App 里的配置列表（* 当前）
  rules append <规则>...         往这份配置里追加规则（--profile <id|名称>，缺省当前配置）
  rules remove <规则>...         从这份配置里删掉这些规则
  dns policy                     这份配置的 DNS 策略
  dns policy set '+.域名=地址[,地址]'...
                                 合并写入 nameserver-policy
  dns policy clear [--fake-ip-filter]
                                 清空 nameserver-policy（或 fake-ip-filter）
  改的是 App 的配置库（store/profiles.json），不重建派生产物；内核还不支持时退出码 5。

不提供: reload、check（配置由 Clash App 管理和检查，退出码 5）。

退出码: 0 成功；1 控制器报错；2 用法；3 连不上；4 密钥被拒；
5 不是 Clash App 的控制器或不支持（含配置库不支持）；6 证书指纹不符或未确认。
`
