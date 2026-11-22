package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

// fakeAppStore is a stand-in controller: it serves the App store endpoints from
// fixture JSON and records the bodies that were written.
type fakeAppStore struct {
	mu           sync.Mutex
	capabilities []string
	profiles     string
	profilesCode int
	rules        map[string]string
	dns          map[string]string
	runtimeRules string
	codes        map[string]int
	puts         []fakePut
}

type fakePut struct {
	Path string
	Body string
}

func (f *fakeAppStore) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	f.mu.Lock()
	defer f.mu.Unlock()
	body, _ := io.ReadAll(r.Body)
	if r.Method == http.MethodPut {
		f.puts = append(f.puts, fakePut{Path: r.URL.Path, Body: string(body)})
	}
	if code := f.codes[r.Method+r.URL.Path]; code != 0 {
		w.WriteHeader(code)
		fmt.Fprint(w, `{"message":"控制器拒绝了这次改动"}`)
		return
	}
	switch {
	case r.URL.Path == "/clash/v1/capabilities":
		_ = json.NewEncoder(w).Encode(capabilities{API: 1, Platform: "macos", CoreVersion: "1.19.32", Capabilities: f.capabilities})
	case r.URL.Path == "/clash/v1/app/profiles":
		if f.profilesCode != 0 {
			w.WriteHeader(f.profilesCode)
			fmt.Fprint(w, `{"message":"the App has not published its profile index yet"}`)
			return
		}
		fmt.Fprint(w, f.profiles)
	case r.URL.Path == "/rules":
		fmt.Fprint(w, f.runtimeRules)
	case strings.HasPrefix(r.URL.Path, "/clash/v1/app/profiles/"):
		rest := strings.TrimPrefix(r.URL.Path, "/clash/v1/app/profiles/")
		id, kind, ok := strings.Cut(rest, "/")
		if !ok {
			http.NotFound(w, r)
			return
		}
		if r.Method == http.MethodPut {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		store := map[string]string{}
		switch kind {
		case "rules":
			store = f.rules
		case "dns-policy":
			store = f.dns
		}
		payload, found := store[id]
		if !found {
			w.WriteHeader(http.StatusNotFound)
			fmt.Fprint(w, `{"message":"unknown profile"}`)
			return
		}
		fmt.Fprint(w, payload)
	default:
		http.NotFound(w, r)
	}
}

func (f *fakeAppStore) written(t *testing.T) (string, map[string]any) {
	t.Helper()
	f.mu.Lock()
	defer f.mu.Unlock()
	if len(f.puts) != 1 {
		t.Fatalf("expected exactly one write, got %d: %+v", len(f.puts), f.puts)
	}
	var decoded map[string]any
	if err := json.Unmarshal([]byte(f.puts[0].Body), &decoded); err != nil {
		t.Fatalf("write body is not JSON (%q): %v", f.puts[0].Body, err)
	}
	return f.puts[0].Path, decoded
}

const testProfileIndex = `{"active":{"profileID":"p2","revision":"r9"},"profiles":[` +
	`{"id":"p1","label":"Home","order":1,"activeRevision":"r3","appendedRules":0},` +
	`{"id":"p2","label":"XSUS","order":-1,"activeRevision":"r9","active":true,"appendedRules":2,"prependedRules":true,"patched":false}]}`

func newAppStoreSession(t *testing.T, store *fakeAppStore) (*session, *bytes.Buffer) {
	t.Helper()
	server := httptest.NewServer(store)
	t.Cleanup(server.Close)
	var stdout, stderr bytes.Buffer
	env := environment{
		getenv: func(string) string { return "" },
		stdin:  strings.NewReader(""),
		stdout: &stdout, stderr: &stderr,
		homeDir: t.TempDir(),
	}
	out := &output{stdout: &stdout, stderr: &stderr}
	s, err := connect(env, globalOptions{url: server.URL, timeout: 3 * time.Second}, out)
	if err != nil {
		t.Fatalf("connect: %v", err)
	}
	return s, &stdout
}

func args(positional ...string) parsedArguments {
	return parsedArguments{positional: positional, flags: map[string]string{}}
}

func withFlags(parsed parsedArguments, pairs ...string) parsedArguments {
	for i := 0; i+1 < len(pairs); i += 2 {
		parsed.flags[pairs[i]] = pairs[i+1]
	}
	return parsed
}

func exitOf(t *testing.T, err error) int {
	t.Helper()
	var cli *cliError
	if !errors.As(err, &cli) {
		t.Fatalf("expected a *cliError, got %v", err)
	}
	return cli.exit
}

func TestAppStoreMissingCapability(t *testing.T) {
	cases := [][]string{
		{"profiles"},
		{"rules", "append", "DOMAIN-SUFFIX,a.com,DIRECT"},
		{"dns", "policy"},
	}
	for _, positional := range cases {
		t.Run(strings.Join(positional, " "), func(t *testing.T) {
			store := &fakeAppStore{profiles: testProfileIndex}
			s, stdout := newAppStoreSession(t, store)
			var err error
			switch positional[0] {
			case "profiles":
				err = cmdAppProfiles(s, args(positional...))
			case "rules":
				err = cmdRules(s, args(positional...))
			case "dns":
				err = cmdDNS(s, args(positional...))
			}
			if err == nil {
				t.Fatalf("expected a capability failure, got none (stdout %q)", stdout.String())
			}
			if exit := exitOf(t, err); exit != exitUnsupported {
				t.Fatalf("expected exit %d, got %d (%v)", exitUnsupported, exit, err)
			}
			if !strings.Contains(err.Error(), "还不支持 App 配置读写") || !strings.Contains(err.Error(), appStoreCapability) {
				t.Fatalf("message should name the missing capability, got %q", err.Error())
			}
			if len(store.puts) != 0 {
				t.Fatalf("nothing should be written, got %+v", store.puts)
			}
		})
	}
}

func TestAppStoreProfilesTable(t *testing.T) {
	store := &fakeAppStore{capabilities: []string{appStoreCapability}, profiles: testProfileIndex}
	s, stdout := newAppStoreSession(t, store)
	if err := cmdAppProfiles(s, args("profiles")); err != nil {
		t.Fatalf("profiles: %v", err)
	}
	output := stdout.String()
	lines := strings.Split(strings.TrimSpace(output), "\n")
	if len(lines) != 3 {
		t.Fatalf("expected a header and two rows, got %q", output)
	}
	for _, want := range []string{"当前", "名称", "id", "修订", "追加规则"} {
		if !strings.Contains(lines[0], want) {
			t.Fatalf("header %q is missing %q", lines[0], want)
		}
	}
	var active, inactive string
	for _, line := range lines[1:] {
		if strings.HasPrefix(strings.TrimSpace(line), "*") {
			active = line
			continue
		}
		inactive = line
	}
	if active == "" || inactive == "" {
		t.Fatalf("expected one marked row and one unmarked row, got %q", output)
	}
	if !strings.Contains(active, "XSUS") {
		t.Fatalf("the marked row should be the active profile, got %q", active)
	}
	if !strings.Contains(active, "p2") || !strings.Contains(active, "r9") || !strings.Contains(active, "2") {
		t.Fatalf("active row should carry id/revision/rule count, got %q", active)
	}
	if !strings.Contains(inactive, "Home") {
		t.Fatalf("inactive row should name the other profile, got %q", inactive)
	}
}

func TestAppStoreProfilesJSON(t *testing.T) {
	store := &fakeAppStore{capabilities: []string{appStoreCapability}, profiles: testProfileIndex}
	s, stdout := newAppStoreSession(t, store)
	s.out.json = true
	if err := cmdAppProfiles(s, args("profiles")); err != nil {
		t.Fatalf("profiles: %v", err)
	}
	var envelope struct {
		OK   bool `json:"ok"`
		Data struct {
			Active struct {
				ProfileID string `json:"profileID"`
				Revision  string `json:"revision"`
			} `json:"active"`
			Profiles []struct {
				ID            string `json:"id"`
				AppendedRules int    `json:"appendedRules"`
			} `json:"profiles"`
		} `json:"data"`
	}
	if err := json.Unmarshal(stdout.Bytes(), &envelope); err != nil {
		t.Fatalf("stdout is not the JSON envelope (%q): %v", stdout.String(), err)
	}
	if !envelope.OK || envelope.Data.Active.ProfileID != "p2" || envelope.Data.Active.Revision != "r9" {
		t.Fatalf("unexpected envelope: %s", stdout.String())
	}
	if len(envelope.Data.Profiles) != 2 || envelope.Data.Profiles[1].AppendedRules != 2 {
		t.Fatalf("profiles should be passed through unchanged: %s", stdout.String())
	}
}

func TestAppStoreProfilesUnpublished(t *testing.T) {
	store := &fakeAppStore{capabilities: []string{appStoreCapability}, profilesCode: http.StatusServiceUnavailable}
	s, _ := newAppStoreSession(t, store)
	err := cmdAppProfiles(s, args("profiles"))
	if exit := exitOf(t, err); exit != exitPeerError {
		t.Fatalf("expected exit %d, got %d (%v)", exitPeerError, exit, err)
	}
	if !strings.Contains(err.Error(), "has not published") {
		t.Fatalf("the controller message should be passed through, got %q", err.Error())
	}
}

func TestAppStoreRulesAppend(t *testing.T) {
	store := &fakeAppStore{
		capabilities: []string{"rules-match-v1", appStoreCapability},
		profiles:     testProfileIndex,
		rules: map[string]string{
			"p2": `{"id":"p2","prependRules":true,"appendRules":["DOMAIN-SUFFIX,a.com,DIRECT","OLD,RULE"],"patchJSON":"{}"}`,
		},
	}
	s, stdout := newAppStoreSession(t, store)
	err := cmdRules(s, args("rules", "append", "DOMAIN-SUFFIX,a.com,DIRECT", "DOMAIN-SUFFIX,b.com,PROXY"))
	if err != nil {
		t.Fatalf("rules append: %v", err)
	}
	path, body := store.written(t)
	if path != "/clash/v1/app/profiles/p2/rules" {
		t.Fatalf("the write should target the active profile, got %q", path)
	}
	if body["prependRules"] != true {
		t.Fatalf("prependRules should be passed through, got %v", body["prependRules"])
	}
	got, _ := body["appendRules"].([]any)
	want := []string{"DOMAIN-SUFFIX,a.com,DIRECT", "OLD,RULE", "DOMAIN-SUFFIX,b.com,PROXY"}
	if len(got) != len(want) {
		t.Fatalf("expected %v, got %v", want, got)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("expected %v, got %v", want, got)
		}
	}
	if _, exists := body["patchJSON"]; exists {
		t.Fatalf("patchJSON is not writable, got %v", body)
	}
	text := stdout.String()
	if !strings.Contains(text, "追加 1 条") || !strings.Contains(text, "共 3 条") {
		t.Fatalf("expected the count and the newly added rules, got %q", text)
	}
	if !strings.Contains(text, "下次连接生效") {
		t.Fatalf("expected the next-connect hint, got %q", text)
	}
	if !strings.Contains(text, "1 条本来就有") {
		t.Fatalf("expected the duplicate note, got %q", text)
	}
}

func TestAppStoreRulesAppendNoop(t *testing.T) {
	store := &fakeAppStore{
		capabilities: []string{appStoreCapability},
		profiles:     testProfileIndex,
		rules: map[string]string{
			"p2": `{"id":"p2","prependRules":false,"appendRules":["OLD,RULE"]}`,
		},
	}
	s, stdout := newAppStoreSession(t, store)
	if err := cmdRules(s, args("rules", "append", "OLD,RULE")); err != nil {
		t.Fatalf("rules append: %v", err)
	}
	if len(store.puts) != 0 {
		t.Fatalf("an unchanged list should not be written, got %+v", store.puts)
	}
	if !strings.Contains(stdout.String(), "没有变化") {
		t.Fatalf("expected a no-op message, got %q", stdout.String())
	}
}

func TestAppStoreRulesRemoveByLabel(t *testing.T) {
	store := &fakeAppStore{
		capabilities: []string{appStoreCapability},
		profiles:     testProfileIndex,
		rules: map[string]string{
			"p1": `{"id":"p1","prependRules":false,"appendRules":["A,RULE","B,RULE"]}`,
			"p2": `{"id":"p2","prependRules":false,"appendRules":["A,RULE","B,RULE","C,RULE"]}`,
		},
	}
	s, stdout := newAppStoreSession(t, store)
	err := cmdRules(s, withFlags(args("rules", "remove", "B,RULE"), "profile", "Home"))
	if err != nil {
		t.Fatalf("rules remove: %v", err)
	}
	path, body := store.written(t)
	if path != "/clash/v1/app/profiles/p1/rules" {
		t.Fatalf("--profile should select by label, got %q", path)
	}
	got, _ := body["appendRules"].([]any)
	if len(got) != 1 || got[0] != "A,RULE" {
		t.Fatalf("only the matching rule should go, got %v", got)
	}
	if !strings.Contains(stdout.String(), "移除 1 条规则") {
		t.Fatalf("expected the removal count, got %q", stdout.String())
	}
}

func TestAppStoreRulesRemoveMatches(t *testing.T) {
	store := &fakeAppStore{
		capabilities: []string{appStoreCapability},
		profiles:     testProfileIndex,
		rules: map[string]string{
			"p2": `{"id":"p2","prependRules":false,"appendRules":["A,RULE","B,RULE","C,RULE"]}`,
		},
	}
	s, _ := newAppStoreSession(t, store)
	if err := cmdRules(s, args("rules", "remove", "B,RULE", "MISSING,RULE")); err != nil {
		t.Fatalf("rules remove: %v", err)
	}
	_, body := store.written(t)
	got, _ := body["appendRules"].([]any)
	if len(got) != 2 || got[0] != "A,RULE" || got[1] != "C,RULE" {
		t.Fatalf("expected the untouched rules in order, got %v", got)
	}
}

func TestAppStoreRulesUnknownProfile(t *testing.T) {
	store := &fakeAppStore{capabilities: []string{appStoreCapability}, profiles: testProfileIndex}
	s, _ := newAppStoreSession(t, store)
	err := cmdRules(s, withFlags(args("rules", "append", "A,RULE"), "profile", "Nope"))
	if exit := exitOf(t, err); exit != exitUsage {
		t.Fatalf("expected exit %d, got %d (%v)", exitUsage, exit, err)
	}
	if !strings.Contains(err.Error(), "--profile") || !strings.Contains(err.Error(), "profiles") {
		t.Fatalf("the message should point at --profile and the profiles command, got %q", err.Error())
	}
	if len(store.puts) != 0 {
		t.Fatalf("nothing should be written, got %+v", store.puts)
	}
}

func TestAppStoreRulesAmbiguousLabel(t *testing.T) {
	store := &fakeAppStore{
		capabilities: []string{appStoreCapability},
		profiles: `{"active":{"profileID":"p1","revision":"r1"},"profiles":[` +
			`{"id":"p1","label":"Same","order":0,"active":true},{"id":"p2","label":"Same","order":1}]}`,
	}
	s, _ := newAppStoreSession(t, store)
	err := cmdRules(s, withFlags(args("rules", "append", "A,RULE"), "profile", "Same"))
	if exit := exitOf(t, err); exit != exitUsage {
		t.Fatalf("expected exit %d, got %d (%v)", exitUsage, exit, err)
	}
	if !strings.Contains(err.Error(), "同名") {
		t.Fatalf("expected a duplicate-label hint, got %q", err.Error())
	}
}

func TestAppStoreRulesWriteRejected(t *testing.T) {
	store := &fakeAppStore{
		capabilities: []string{appStoreCapability},
		profiles:     testProfileIndex,
		rules: map[string]string{
			"p2": `{"id":"p2","prependRules":false,"appendRules":[]}`,
		},
		codes: map[string]int{"PUT/clash/v1/app/profiles/p2/rules": http.StatusBadRequest},
	}
	s, stdout := newAppStoreSession(t, store)
	err := cmdRules(s, args("rules", "append", "TOO,LONG"))
	if exit := exitOf(t, err); exit != exitPeerError {
		t.Fatalf("expected exit %d, got %d (%v)", exitPeerError, exit, err)
	}
	if !strings.Contains(err.Error(), "控制器拒绝了这次改动") {
		t.Fatalf("the controller message should be passed through, got %q", err.Error())
	}
	if strings.Contains(stdout.String(), "✓") {
		t.Fatalf("a rejected write should not claim success, got %q", stdout.String())
	}
}

func TestAppStoreDNSPolicyShow(t *testing.T) {
	store := &fakeAppStore{
		capabilities: []string{appStoreCapability},
		profiles:     testProfileIndex,
		dns: map[string]string{
			"p2": `{"nameserverPolicy":{"+.didichuxing.com":["10.78.226.116"]},"fakeIPFilter":["+.example.com"]}`,
		},
	}
	s, stdout := newAppStoreSession(t, store)
	if err := cmdDNS(s, args("dns", "policy")); err != nil {
		t.Fatalf("dns policy: %v", err)
	}
	text := stdout.String()
	for _, want := range []string{"DNS 策略：XSUS（p2）", "+.didichuxing.com → 10.78.226.116", "+.example.com"} {
		if !strings.Contains(text, want) {
			t.Fatalf("expected %q in the output, got %q", want, text)
		}
	}
}

func TestAppStoreDNSPolicyShowEmpty(t *testing.T) {
	store := &fakeAppStore{
		capabilities: []string{appStoreCapability},
		profiles:     testProfileIndex,
		dns:          map[string]string{"p2": `{}`},
	}
	s, stdout := newAppStoreSession(t, store)
	if err := cmdDNS(s, args("dns", "policy")); err != nil {
		t.Fatalf("dns policy: %v", err)
	}
	if !strings.Contains(stdout.String(), "nameserver-policy：没有设置") || !strings.Contains(stdout.String(), "fake-ip-filter：没有设置") {
		t.Fatalf("empty parts should say so, got %q", stdout.String())
	}
}

func TestAppStoreDNSPolicySetMerges(t *testing.T) {
	store := &fakeAppStore{
		capabilities: []string{appStoreCapability},
		profiles:     testProfileIndex,
		dns: map[string]string{
			"p2": `{"nameserverPolicy":{"+.a.com":["1.1.1.1"]},"fakeIPFilter":["+.keep.com"]}`,
		},
	}
	s, stdout := newAppStoreSession(t, store)
	err := cmdDNS(s, args("dns", "policy", "set", "+.b.com=2.2.2.2, 3.3.3.3"))
	if err != nil {
		t.Fatalf("dns policy set: %v", err)
	}
	path, body := store.written(t)
	if path != "/clash/v1/app/profiles/p2/dns-policy" {
		t.Fatalf("unexpected path %q", path)
	}
	if _, exists := body["fakeIPFilter"]; exists {
		t.Fatalf("fakeIPFilter should be left alone, got %v", body)
	}
	policy, _ := body["nameserverPolicy"].(map[string]any)
	if len(policy) != 2 {
		t.Fatalf("the existing entry should be merged, got %v", policy)
	}
	servers, _ := policy["+.b.com"].([]any)
	if len(servers) != 2 || servers[0] != "2.2.2.2" || servers[1] != "3.3.3.3" {
		t.Fatalf("expected two trimmed servers, got %v", policy["+.b.com"])
	}
	if !strings.Contains(stdout.String(), "写入 1 条") {
		t.Fatalf("expected the merged count, got %q", stdout.String())
	}
}

func TestAppStoreDNSPolicySetRejectsBadPair(t *testing.T) {
	store := &fakeAppStore{capabilities: []string{appStoreCapability}, profiles: testProfileIndex, dns: map[string]string{"p2": `{}`}}
	s, _ := newAppStoreSession(t, store)
	err := cmdDNS(s, args("dns", "policy", "set", "+.b.com"))
	if exit := exitOf(t, err); exit != exitUsage {
		t.Fatalf("expected exit %d, got %d (%v)", exitUsage, exit, err)
	}
}

func TestAppStoreDNSPolicyClear(t *testing.T) {
	store := &fakeAppStore{
		capabilities: []string{appStoreCapability},
		profiles:     testProfileIndex,
		dns: map[string]string{
			"p2": `{"nameserverPolicy":{"+.a.com":["1.1.1.1"]},"fakeIPFilter":["+.keep.com"]}`,
		},
	}
	s, stdout := newAppStoreSession(t, store)
	if err := cmdDNS(s, args("dns", "policy", "clear")); err != nil {
		t.Fatalf("dns policy clear: %v", err)
	}
	_, body := store.written(t)
	policy, ok := body["nameserverPolicy"].(map[string]any)
	if !ok || len(policy) != 0 {
		t.Fatalf("clear should send an empty nameserverPolicy, got %v", body)
	}
	if _, exists := body["fakeIPFilter"]; exists {
		t.Fatalf("fakeIPFilter should be left alone, got %v", body)
	}
	if !strings.Contains(stdout.String(), "已清空 XSUS（p2）的 nameserver-policy") {
		t.Fatalf("expected the clear message, got %q", stdout.String())
	}
}

func TestAppStoreDNSPolicyClearFakeIPFilter(t *testing.T) {
	store := &fakeAppStore{
		capabilities: []string{appStoreCapability},
		profiles:     testProfileIndex,
		dns:          map[string]string{"p2": `{"fakeIPFilter":["+.keep.com"]}`},
	}
	s, _ := newAppStoreSession(t, store)
	if err := cmdDNS(s, withFlags(args("dns", "policy", "clear"), "fake-ip-filter", "1")); err != nil {
		t.Fatalf("dns policy clear --fake-ip-filter: %v", err)
	}
	_, body := store.written(t)
	if _, exists := body["nameserverPolicy"]; exists {
		t.Fatalf("nameserverPolicy should be left alone, got %v", body)
	}
	filter, ok := body["fakeIPFilter"].([]any)
	if !ok || len(filter) != 0 {
		t.Fatalf("expected an empty fakeIPFilter, got %v", body)
	}
}

func TestAppStoreRuntimeRulesUnchanged(t *testing.T) {
	store := &fakeAppStore{
		profiles:     testProfileIndex,
		runtimeRules: `{"rules":[{"type":"DOMAIN-SUFFIX","payload":"a.com","proxy":"DIRECT"}]}`,
	}
	s, stdout := newAppStoreSession(t, store)
	if err := cmdRules(s, args("rules", "5")); err != nil {
		t.Fatalf("rules 5: %v", err)
	}
	if !strings.Contains(stdout.String(), "规则 1 条") {
		t.Fatalf("the running rule list should still work, got %q", stdout.String())
	}
	if len(store.puts) != 0 {
		t.Fatalf("reading rules must not write, got %+v", store.puts)
	}
}

func TestMergeAppendRules(t *testing.T) {
	merged, appended := mergeAppendRules([]string{"A", "B", "A"}, []string{"B", "C", "C", "D"})
	if appended != 2 {
		t.Fatalf("expected 2 new rules, got %d (%v)", appended, merged)
	}
	want := []string{"A", "B", "C", "D"}
	if len(merged) != len(want) {
		t.Fatalf("expected %v, got %v", want, merged)
	}
	for i := range want {
		if merged[i] != want[i] {
			t.Fatalf("expected %v, got %v", want, merged)
		}
	}
}

func TestAppStoreRunReportsMissingCapability(t *testing.T) {
	store := &fakeAppStore{profiles: testProfileIndex}
	server := httptest.NewServer(store)
	defer server.Close()
	for _, tc := range []struct {
		name string
		args []string
	}{{"human", []string{"profiles"}}, {"json", []string{"--json", "profiles"}}} {
		t.Run(tc.name, func(t *testing.T) {
			var stdout, stderr bytes.Buffer
			env := environment{
				args: tc.args,
				getenv: func(key string) string {
					if key == "CLASH_API" {
						return server.URL
					}
					return ""
				},
				stdin:  strings.NewReader(""),
				stdout: &stdout, stderr: &stderr,
				homeDir: t.TempDir(),
			}
			if exit := run(env); exit != exitUnsupported {
				t.Fatalf("expected exit %d, got %d (stdout %q, stderr %q)", exitUnsupported, exit, stdout.String(), stderr.String())
			}
			if tc.name == "human" {
				if !strings.Contains(stderr.String(), "还不支持 App 配置读写") {
					t.Fatalf("expected the hint on stderr, got %q", stderr.String())
				}
				return
			}
			var envelope struct {
				OK    bool `json:"ok"`
				Error struct {
					Code    string `json:"code"`
					Message string `json:"message"`
				} `json:"error"`
			}
			if err := json.Unmarshal(stdout.Bytes(), &envelope); err != nil {
				t.Fatalf("stdout is not a JSON envelope (%q): %v", stdout.String(), err)
			}
			if envelope.OK || envelope.Error.Code != "unsupported" || !strings.Contains(envelope.Error.Message, appStoreCapability) {
				t.Fatalf("unexpected envelope: %s", stdout.String())
			}
		})
	}
}

// Writing the profile store is refused on a controller listener; the refusal
// must point at the App Group socket instead of blaming the secret.
func TestWriteRefusalPointsAtTheSocket(t *testing.T) {
	refusal := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.URL.Path == "/clash/v1/capabilities":
			_ = json.NewEncoder(w).Encode(capabilities{API: 1, Platform: "macos", CoreVersion: "1.19.32", Capabilities: []string{appStoreCapability}})
		case r.URL.Path == "/clash/v1/app/profiles":
			fmt.Fprint(w, testProfileIndex)
		case r.URL.Path == "/clash/v1/app/profiles/p2/rules" && r.Method == http.MethodPut:
			w.Header().Set("X-Clash-Refusal", appStoreLocalWritesOnly)
			w.WriteHeader(http.StatusForbidden)
			fmt.Fprint(w, "the App profile store accepts writes only over the App Group socket; LAN controller clients are read-only")
		case r.URL.Path == "/clash/v1/app/profiles/p2/rules":
			fmt.Fprint(w, `{"id":"p2","prependRules":false,"appendRules":[],"patchJSON":"{}"}`)
		default:
			http.NotFound(w, r)
		}
	})
	server := httptest.NewServer(refusal)
	defer server.Close()

	var stdout, stderr bytes.Buffer
	env := environment{
		getenv: func(key string) string {
			if key == "CLASH_API" {
				return server.URL
			}
			return ""
		},
		stdin: strings.NewReader(""), stdout: &stdout, stderr: &stderr, homeDir: t.TempDir(),
	}
	out := &output{stdout: &stdout, stderr: &stderr}
	s, err := connect(env, globalOptions{url: server.URL, timeout: 3 * time.Second}, out)
	if err != nil {
		t.Fatalf("connect: %v", err)
	}
	err = cmdRules(s, args("rules", "append", "DOMAIN,refused.example,DIRECT"))
	if err == nil {
		t.Fatal("a refused write was reported as success")
	}
	if exit := exitOf(t, err); exit != exitPeerError {
		t.Fatalf("refusal exit = %d, want %d (%v)", exit, exitPeerError, err)
	}
	message := err.Error()
	if !strings.Contains(message, "--socket") || !strings.Contains(message, "App Group socket") {
		t.Fatalf("the refusal should point at --socket, got %q", message)
	}
	if strings.Contains(message, "密钥") {
		t.Fatalf("a policy refusal must not blame the secret, got %q", message)
	}
}

// --socket sends the same requests over the App Group socket, which is the
// only place the store accepts writes.
func TestSocketOptionWritesOverTheAppGroupSocket(t *testing.T) {
	store := &fakeAppStore{
		capabilities: []string{appStoreCapability},
		profiles:     testProfileIndex,
		rules: map[string]string{
			"p2": `{"id":"p2","prependRules":false,"appendRules":[],"patchJSON":"{}"}`,
		},
	}
	directory, err := os.MkdirTemp("/tmp", "clash-cli-socket")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(directory) })
	socket := filepath.Join(directory, "clash.sock")
	listener, err := net.Listen("unix", socket)
	if err != nil {
		t.Fatalf("listen on %s: %v", socket, err)
	}
	server := &http.Server{Handler: store}
	go func() { _ = server.Serve(listener) }()
	t.Cleanup(func() { _ = server.Close() })

	var stdout, stderr bytes.Buffer
	env := environment{getenv: func(string) string { return "" }, stdin: strings.NewReader(""),
		stdout: &stdout, stderr: &stderr, homeDir: t.TempDir()}
	out := &output{stdout: &stdout, stderr: &stderr}
	s, err := connect(env, globalOptions{url: "http://127.0.0.1:9090", socket: socket, timeout: 3 * time.Second}, out)
	if err != nil {
		t.Fatalf("connect over %s: %v", socket, err)
	}
	if err := cmdRules(s, args("rules", "append", "DOMAIN,via-socket.example,DIRECT")); err != nil {
		t.Fatalf("rules append over the socket: %v (stderr %q)", err, stderr.String())
	}
	path, body := store.written(t)
	if path != "/clash/v1/app/profiles/p2/rules" {
		t.Fatalf("the write should target the active profile over the socket, got %q", path)
	}
	if rules, _ := body["appendRules"].([]any); len(rules) != 1 || rules[0] != "DOMAIN,via-socket.example,DIRECT" {
		t.Fatalf("appendRules = %v", body["appendRules"])
	}
}
