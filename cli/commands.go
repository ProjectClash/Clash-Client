package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/signal"
	"slices"
	"sort"
	"strconv"
	"strings"
	"time"
)

type commandHandler func(*session, parsedArguments) error

var commands map[string]commandHandler

func init() {
	commands = map[string]commandHandler{
		"status":      cmdStatus,
		"proxies":     cmdProxies,
		"proxy":       cmdProxy,
		"test":        cmdTest,
		"grouptest":   cmdGroupTestEachMember,
		"connections": cmdConnections,
		"conn":        cmdConn,
		"traffic":     cmdTraffic,
		"rules":       cmdRules,
		"configs":     cmdConfigs,
		"dns":         cmdDNS,
		"logs":        cmdLogs,
		"log":         cmdLogs,
		"mode":        cmdMode,
		"group":       cmdGroup,
		"provider":    cmdProvider,
		"rule":        cmdRule,
		"flush":       cmdFlush,
	}
}

const (
	defaultTestURL          = "https://www.gstatic.com/generate_204"
	defaultDelayTimeoutMS   = 5000
	defaultConnectionsShown = 20
	defaultRulesShown       = 10
	defaultStreamSeconds    = 3
)

func pathEscape(name string) string { return url.PathEscape(name) }

func usage(format string, args ...any) error {
	return failure(exitUsage, "usage", "用法: "+format, args...)
}

func (s *session) announce() {
	if s.out.json {
		return
	}
	platform := map[string]string{"ios": "iPhone/iPad", "macos": "Mac", "tvos": "Apple TV"}[s.caps.Platform]
	if platform == "" {
		platform = s.caps.Platform
	}
	s.out.printf("%s\n", s.out.dim(fmt.Sprintf("[%s · %s · 内核 %s]", s.base.Host, platform, s.caps.CoreVersion)))
}

type proxyEntry struct {
	Name    string          `json:"name"`
	Type    string          `json:"type"`
	Now     string          `json:"now,omitempty"`
	All     []string        `json:"all,omitempty"`
	Fixed   string          `json:"fixed,omitempty"`
	Hidden  bool            `json:"hidden,omitempty"`
	History []delayRecord   `json:"history,omitempty"`
	Extra   json.RawMessage `json:"-"`
}

type delayRecord struct {
	Time  string `json:"time"`
	Delay int    `json:"delay"`
}

var groupTypes = []string{"Selector", "URLTest", "Fallback", "LoadBalance", "Relay"}

func isGroup(entry proxyEntry) bool { return slices.Contains(groupTypes, entry.Type) }

func (s *session) proxies() (map[string]proxyEntry, error) {
	var reply struct {
		Proxies map[string]proxyEntry `json:"proxies"`
	}
	if err := s.call(http.MethodGet, "/proxies", nil, nil, &reply); err != nil {
		return nil, err
	}
	return reply.Proxies, nil
}

func sortedGroups(entries map[string]proxyEntry) []proxyEntry {
	var groups []proxyEntry
	for name, entry := range entries {
		entry.Name = name
		if isGroup(entry) {
			groups = append(groups, entry)
		}
	}
	order := map[string]int{}
	if global, ok := entries["GLOBAL"]; ok {
		for i, name := range global.All {
			order[name] = i + 1
		}
	}
	sort.SliceStable(groups, func(i, j int) bool {
		a, b := order[groups[i].Name], order[groups[j].Name]
		if a != b {
			if a == 0 || b == 0 {
				return b == 0
			}
			return a < b
		}
		return groups[i].Name < groups[j].Name
	})
	return groups
}

func cmdStatus(s *session, _ parsedArguments) error {
	var version, configs, memory, traffic, remote map[string]any
	var connections struct {
		DownloadTotal int64 `json:"downloadTotal"`
		UploadTotal   int64 `json:"uploadTotal"`
		Connections   []any `json:"connections"`
	}
	for _, step := range []struct {
		path string
		into any
	}{{"/version", &version}, {"/configs", &configs}, {"/clash/v1/memory", &memory},
		{"/clash/v1/traffic", &traffic}, {"/connections", &connections}, {"/clash/v1/remote-control", &remote}} {
		if err := s.call(http.MethodGet, step.path, nil, nil, step.into); err != nil {
			return err
		}
	}
	entries, err := s.proxies()
	if err != nil {
		return err
	}
	groups := sortedGroups(entries)
	type groupNow struct {
		Name string `json:"name"`
		Type string `json:"type"`
		Now  string `json:"now"`
	}
	groupList := make([]groupNow, 0, len(groups))
	for _, group := range groups {
		groupList = append(groupList, groupNow{group.Name, group.Type, group.Now})
	}
	listen, listenKnown := listenOf(configs)
	data := map[string]any{
		"version": version, "configs": configs, "memory": memory, "traffic": traffic,
		"connections":   map[string]any{"count": len(connections.Connections), "downloadTotal": connections.DownloadTotal, "uploadTotal": connections.UploadTotal},
		"capabilities":  s.caps,
		"remoteControl": remote,
		"groups":        groupList,
	}
	if listenKnown {
		data["listen"] = listen
	}
	s.out.succeed(data, func() {
		tun, _ := configs["tun"].(map[string]any)
		s.out.printf("Clash %v  meta=%v  （%s，控制器 API %d）\n", version["version"], version["meta"], s.caps.Platform, s.caps.API)
		s.out.printf("mode=%v  mixed-port=%v  tun=%v stack=%v\n", configs["mode"], configs["mixed-port"], tun["enable"], tun["stack"])
		if listenKnown {
			s.out.printf("%s\n", listen.line())
		}
		footprint, _ := memory["footprint"].(float64)
		inuse, _ := memory["inuse"].(float64)
		s.out.printf("内存 %dMB（RSS %dMB）\n", int64(footprint)/1024/1024, int64(inuse)/1024/1024)
		up, _ := traffic["up"].(float64)
		down, _ := traffic["down"].(float64)
		s.out.printf("流量 ↑%s ↓%s  连接 %d 个（总 ↓%s ↑%s）\n", formatRate(up), formatRate(down), len(connections.Connections),
			formatBytes(float64(connections.DownloadTotal)), formatBytes(float64(connections.UploadTotal)))
		if mode, _ := remote["mode"].(string); mode != "" && mode != "config" {
			http, _ := remote["http"].(map[string]any)
			tls, _ := remote["tls"].(map[string]any)
			s.out.printf("外部控制器 %s  http=%v  tls=%v\n", mode, http["address"], tls["address"])
		}
		s.out.printf("策略组 %d 个：\n", len(groups))
		for _, group := range groups {
			s.out.printf("  %s → %s\n", padRight(group.Name, 20), group.Now)
		}
	})
	return nil
}

func padRight(text string, width int) string {
	if gap := width - displayWidth(text); gap > 0 {
		return text + strings.Repeat(" ", gap)
	}
	return text
}

func cmdConfigs(s *session, _ parsedArguments) error {
	var configs map[string]any
	if err := s.call(http.MethodGet, "/configs", nil, nil, &configs); err != nil {
		return err
	}
	s.out.succeed(configs, func() { printJSON(s.out, configs) })
	return nil
}

type listenAddress struct {
	Host  string         `json:"host"`
	Reach string         `json:"reach"`
	Ports map[string]int `json:"ports"`
	why   string
}

var allowLanPorts = []string{"mixed-port", "port", "socks-port", "redir-port", "tproxy-port"}

func listenOf(configs map[string]any) (listenAddress, bool) {
	allowLan, known := configs["allow-lan"].(bool)
	if !known {
		return listenAddress{}, false
	}
	ports := map[string]int{}
	for _, name := range allowLanPorts {
		if port, _ := configs[name].(float64); port > 0 {
			ports[name] = int(port)
		}
	}
	if len(ports) == 0 {
		return listenAddress{}, false
	}
	bind, _ := configs["bind-address"].(string)
	listen := listenAddress{Ports: ports}
	switch {
	case !allowLan:
		listen.Host, listen.Reach = "127.0.0.1", "loopback"
		listen.why = "allow-lan=false：只有运行 Clash 的这台设备连得上，bind-address 不起作用。false 可能是文件里写的，也可能是 App 里「允许局域网连接」关着改的"
	case bind == "" || bind == "*" || bind == "0.0.0.0" || bind == "::" || bind == "[::]":
		listen.Host, listen.Reach = "*", "any"
		listen.why = "allow-lan=true，bind-address " + bind + lanFilter(configs)
		if bind == "" {
			listen.why = "allow-lan=true" + lanFilter(configs)
		}
	default:
		listen.Host, listen.Reach = bind, "address"
		listen.why = "allow-lan=true，bind-address 指定了这个地址" + lanFilter(configs)
		if ip := net.ParseIP(strings.Trim(bind, "[]")); (ip != nil && ip.IsLoopback()) || bind == "localhost" {
			listen.Reach = "loopback"
			listen.why = "allow-lan=true，但 bind-address 是回环地址：只有运行 Clash 的这台设备连得上"
		}
	}
	return listen, true
}

func lanFilter(configs map[string]any) string {
	var parts []string
	allowed := stringList(configs["lan-allowed-ips"])
	if len(allowed) > 0 && !slices.Equal(allowed, []string{"0.0.0.0/0", "::/0"}) {
		parts = append(parts, "只放行 lan-allowed-ips 里的 "+strings.Join(allowed, " "))
	}
	if refused := stringList(configs["lan-disallowed-ips"]); len(refused) > 0 {
		parts = append(parts, "不放行 lan-disallowed-ips 里的 "+strings.Join(refused, " "))
	}
	if len(parts) == 0 {
		return ""
	}
	return "；" + strings.Join(parts, "，")
}

func stringList(value any) []string {
	items, _ := value.([]any)
	list := make([]string, 0, len(items))
	for _, item := range items {
		if text, ok := item.(string); ok {
			list = append(list, text)
		}
	}
	return list
}

func (l listenAddress) line() string {
	ports := make([]string, 0, len(l.Ports))
	for _, name := range allowLanPorts {
		if port, ok := l.Ports[name]; ok {
			ports = append(ports, fmt.Sprintf("%s %d", name, port))
		}
	}
	return fmt.Sprintf("监听 %s：%s（%s）", l.Host, strings.Join(ports, "、"), l.why)
}

func printJSON(out *output, value any) {
	data, _ := json.MarshalIndent(value, "", "  ")
	out.printf("%s\n", data)
}

func cmdMode(s *session, p parsedArguments) error {
	args := p.positional[1:]
	if len(args) == 0 {
		var configs map[string]any
		if err := s.call(http.MethodGet, "/configs", nil, nil, &configs); err != nil {
			return err
		}
		s.out.succeed(map[string]any{"mode": configs["mode"]}, func() { s.out.printf("mode=%v\n", configs["mode"]) })
		return nil
	}
	mode := strings.ToLower(args[0])
	if mode != "rule" && mode != "global" && mode != "direct" {
		return usage("clash-cli mode [rule|global|direct]")
	}
	s.announce()
	if err := s.call(http.MethodPatch, "/configs", nil, map[string]string{"mode": mode}, nil); err != nil {
		return err
	}
	s.out.succeed(map[string]any{"mode": mode}, func() { s.out.printf("✓ mode → %s\n", mode) })
	return nil
}

func (s *session) proxy(name string) (proxyEntry, error) {
	var entry proxyEntry
	err := s.call(http.MethodGet, "/proxies/"+pathEscape(name), nil, nil, &entry)
	return entry, err
}

func cmdProxies(s *session, p parsedArguments) error {
	if len(p.positional) > 1 {
		return showGroupMembers(s, p.positional[1])
	}
	return listGroupsAndNodes(s)
}

func listGroupsAndNodes(s *session) error {
	entries, err := s.proxies()
	if err != nil {
		return err
	}
	groups := sortedGroups(entries)
	var leaves []proxyEntry
	for name, entry := range entries {
		entry.Name = name
		if !isGroup(entry) {
			leaves = append(leaves, entry)
		}
	}
	sort.Slice(leaves, func(i, j int) bool { return leaves[i].Name < leaves[j].Name })
	s.out.succeed(map[string]any{"groups": groups, "nodes": leaves}, func() {
		s.out.printf("策略组 %d 个：\n", len(groups))
		for _, group := range groups {
			s.out.printf("  %s [%s] → %s\n", padRight(group.Name, 20), group.Type, firstNonEmpty(group.Now, "-"))
		}
		s.out.printf("\n节点 %d 个（名称/类型）：\n", len(leaves))
		for _, leaf := range leaves {
			s.out.printf("  %s  (%s)\n", leaf.Name, leaf.Type)
		}
	})
	return nil
}

func showGroupMembers(s *session, name string) error {
	entry, err := s.proxy(name)
	if err != nil {
		return err
	}
	s.out.succeed(entry, func() {
		s.out.printf("名称: %s  类型: %s  now: %s\n", entry.Name, entry.Type, firstNonEmpty(entry.Now, "-"))
		if entry.Fixed != "" {
			s.out.printf("固定: %s\n", entry.Fixed)
		}
		if len(entry.All) > 0 {
			s.out.printf("成员 (%d):\n", len(entry.All))
			for _, member := range entry.All {
				s.out.printf("  - %s\n", member)
			}
		}
	})
	return nil
}

func cmdProxy(s *session, p parsedArguments) error {
	args := p.positional[1:]
	if len(args) == 0 {
		return usage("clash-cli proxy get <组> | clash-cli proxy set <组> <节点> | clash-cli proxy test <节点> [url] [timeout_ms]")
	}
	switch args[0] {
	case "get":
		if len(args) < 2 {
			return usage("clash-cli proxy get <组>")
		}
		return groupGet(s, args[1])
	case "set":
		if len(args) < 3 {
			return usage("clash-cli proxy set <组> <节点>")
		}
		return groupSelect(s, args[1], args[2])
	case "test":
		if len(args) < 2 {
			return usage("clash-cli proxy test <节点> [url] [timeout_ms]")
		}
		return testProxy(s, args[1], args[2:], p)
	}
	return usage("clash-cli proxy get <组> | clash-cli proxy set <组> <节点> | clash-cli proxy test <节点> [url] [timeout_ms]")
}

func groupGet(s *session, name string) error {
	entry, err := s.proxy(name)
	if err != nil {
		return err
	}
	s.out.succeed(entry, func() {
		s.out.printf("%s → %s  [%s]\n", name, firstNonEmpty(entry.Now, "-"), entry.Type)
		if len(entry.All) > 0 {
			s.out.printf("可选: %s\n", strings.Join(entry.All, ", "))
		}
	})
	return nil
}

func groupSelect(s *session, group, node string) error {
	entry, err := s.proxy(group)
	if err != nil {
		return err
	}
	if len(entry.All) > 0 && !slices.Contains(entry.All, node) {
		return failure(exitPeerError, "no-such-member", "%s 没有成员 %q（节点名要逐字一致，含 emoji 与空格；clash-cli proxies %s 列出成员）", group, node, group)
	}
	s.announce()
	if err := s.call(http.MethodPut, "/proxies/"+pathEscape(group), nil, map[string]string{"name": node}, nil); err != nil {
		return err
	}
	after, err := s.proxy(group)
	if err != nil {
		return err
	}
	s.out.succeed(after, func() { s.out.printf("✓ %s → %s\n", group, after.Now) })
	return nil
}

func cmdGroup(s *session, p parsedArguments) error {
	args := p.positional[1:]
	if len(args) == 0 {
		return usage("clash-cli group list | show <组> | select <组> <节点> | unfix <组> | test <组> [url] [timeout_ms]")
	}
	switch args[0] {
	case "list":
		return listGroupsAndNodes(s)
	case "show":
		if len(args) < 2 {
			return usage("clash-cli group show <组>")
		}
		return showGroupMembers(s, args[1])
	case "select":
		if len(args) < 3 {
			return usage("clash-cli group select <组> <节点>")
		}
		return groupSelect(s, args[1], args[2])
	case "unfix":
		if len(args) < 2 {
			return usage("clash-cli group unfix <组>")
		}
		s.announce()
		if err := s.call(http.MethodDelete, "/proxies/"+pathEscape(args[1]), nil, nil, nil); err != nil {
			return err
		}
		after, err := s.proxy(args[1])
		if err != nil {
			return err
		}
		s.out.succeed(after, func() { s.out.printf("✓ %s 已解除固定 → %s\n", args[1], firstNonEmpty(after.Now, "-")) })
		return nil
	case "test":
		if len(args) < 2 {
			return usage("clash-cli group test <组> [url] [timeout_ms]")
		}
		return groupTestThroughGroup(s, args[1], args[2:], p)
	}
	return usage("clash-cli group list | show <组> | select <组> <节点> | unfix <组> | test <组> [url] [timeout_ms]")
}

func testParameters(rest []string, p parsedArguments) (string, int, error) {
	testURL := firstNonEmpty(p.flags["test-url"], defaultTestURL)
	timeout := defaultDelayTimeoutMS
	if len(rest) > 0 {
		testURL = rest[0]
	}
	timeoutText := p.flags["delay-timeout"]
	if len(rest) > 1 {
		timeoutText = rest[1]
	}
	if timeoutText != "" {
		value, err := strconv.Atoi(timeoutText)
		if err != nil || value <= 0 {
			return "", 0, usage("timeout_ms 是正整数（毫秒），收到 %q", timeoutText)
		}
		timeout = value
	}
	return testURL, timeout, nil
}

func (s *session) delayClient(timeoutMS int) *http.Client {
	client := *s.client
	client.Timeout = time.Duration(timeoutMS)*time.Millisecond + 5*time.Second
	return &client
}

func (s *session) delay(name, testURL string, timeoutMS int) (int, error) {
	query := url.Values{"url": {testURL}, "timeout": {strconv.Itoa(timeoutMS)}}
	response, err := s.request(context.Background(), s.delayClient(timeoutMS), http.MethodGet, "/proxies/"+pathEscape(name)+"/delay", query, nil)
	if err != nil {
		return 0, err
	}
	defer response.Body.Close()
	if response.StatusCode >= 400 {
		return 0, peerFailure(response)
	}
	var reply struct {
		Delay int `json:"delay"`
	}
	if err := json.NewDecoder(response.Body).Decode(&reply); err != nil {
		return 0, failure(exitPeerError, "bad-response", "延迟结果不是 JSON: %v", err)
	}
	return reply.Delay, nil
}

func cmdTest(s *session, p parsedArguments) error {
	if len(p.positional) < 2 {
		return usage("clash-cli test <名称> [url] [timeout_ms]")
	}
	return testProxy(s, p.positional[1], p.positional[2:], p)
}

func testProxy(s *session, name string, rest []string, p parsedArguments) error {
	testURL, timeout, err := testParameters(rest, p)
	if err != nil {
		return err
	}
	delay, err := s.delay(name, testURL, timeout)
	if err != nil {
		if !s.out.json {
			s.out.printf("✗ %s 测试失败: %v\n", name, err)
		}
		return err
	}
	s.out.succeed(map[string]any{"name": name, "delay": delay, "url": testURL}, func() { s.out.printf("✓ %s 延迟 %dms\n", name, delay) })
	return nil
}

func cmdGroupTestEachMember(s *session, p parsedArguments) error {
	if len(p.positional) < 2 {
		return usage("clash-cli grouptest <组名> [url] [timeout_ms]")
	}
	group := p.positional[1]
	testURL, timeout, err := testParameters(p.positional[2:], p)
	if err != nil {
		return err
	}
	entry, err := s.proxy(group)
	if err != nil {
		return err
	}
	if !s.out.json {
		s.out.printf("%s 成员 %d 个，测速中...\n", group, len(entry.All))
	}
	results := map[string]any{}
	for _, member := range entry.All {
		delay, err := s.delay(member, testURL, timeout)
		if err != nil {
			results[member] = nil
			if !s.out.json {
				s.out.printf("  %s   超时/失败\n", padRight(member, 40))
			}
			continue
		}
		results[member] = delay
		if !s.out.json {
			s.out.printf("  %s %6dms\n", padRight(member, 40), delay)
		}
	}
	if s.out.json {
		s.out.succeed(map[string]any{"group": group, "url": testURL, "delays": results}, nil)
	}
	return nil
}

func groupTestThroughGroup(s *session, group string, rest []string, p parsedArguments) error {
	testURL, timeout, err := testParameters(rest, p)
	if err != nil {
		return err
	}
	if !s.out.json {
		s.out.printf("注意：对 URLTest/Fallback 组，这次测速会先解除该组的固定选择（不想改动选择请用 clash-cli grouptest %s）。\n", group)
	}
	s.announce()
	query := url.Values{"url": {testURL}, "timeout": {strconv.Itoa(timeout)}}
	response, err := s.request(context.Background(), s.delayClient(timeout), http.MethodGet, "/group/"+pathEscape(group)+"/delay", query, nil)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode >= 400 {
		return peerFailure(response)
	}
	var delays map[string]int
	if err := json.NewDecoder(response.Body).Decode(&delays); err != nil {
		return failure(exitPeerError, "bad-response", "组测速结果不是 JSON: %v", err)
	}
	names := make([]string, 0, len(delays))
	for name := range delays {
		names = append(names, name)
	}
	sort.Slice(names, func(i, j int) bool { return delays[names[i]] < delays[names[j]] })
	s.out.succeed(map[string]any{"group": group, "url": testURL, "delays": delays}, func() {
		for _, name := range names {
			s.out.printf("  %s %6dms\n", padRight(name, 40), delays[name])
		}
	})
	return nil
}

func cmdProvider(s *session, p parsedArguments) error {
	args := p.positional[1:]
	if len(args) == 0 {
		return usage("clash-cli provider list | update proxy|rule <名称> | test <节点集>")
	}
	switch args[0] {
	case "list":
		var proxySets, ruleSets struct {
			Providers map[string]map[string]any `json:"providers"`
		}
		if err := s.call(http.MethodGet, "/providers/proxies", nil, nil, &proxySets); err != nil {
			return err
		}
		if err := s.call(http.MethodGet, "/providers/rules", nil, nil, &ruleSets); err != nil {
			return err
		}
		s.out.succeed(map[string]any{"proxies": proxySets.Providers, "rules": ruleSets.Providers}, func() {
			var rows [][]string
			for _, kind := range []struct {
				label string
				sets  map[string]map[string]any
			}{{"节点集", proxySets.Providers}, {"规则集", ruleSets.Providers}} {
				names := make([]string, 0, len(kind.sets))
				for name, set := range kind.sets {
					if set["vehicleType"] == "Compatible" {
						continue
					}
					names = append(names, name)
				}
				sort.Strings(names)
				for _, name := range names {
					set := kind.sets[name]
					count := fmt.Sprint(set["ruleCount"])
					if members, ok := set["proxies"].([]any); ok {
						count = strconv.Itoa(len(members))
					}
					rows = append(rows, []string{kind.label, name, fmt.Sprint(set["vehicleType"]), count, fmt.Sprint(set["updatedAt"])})
				}
			}
			if len(rows) == 0 {
				s.out.printf("没有节点集或规则集\n")
				return
			}
			s.out.table([]string{"种类", "名称", "来源", "条目", "更新于"}, rows)
		})
		return nil
	case "update":
		if len(args) < 3 || (args[1] != "proxy" && args[1] != "rule") {
			return usage("clash-cli provider update proxy|rule <名称>")
		}
		if err := s.require("provider-update-v1"); err != nil {
			return err
		}
		s.announce()
		client := *s.client
		client.Timeout = 65 * time.Second
		response, err := s.request(context.Background(), &client, http.MethodPost, "/clash/v1/provider-update", nil,
			map[string]any{"kind": args[1], "name": args[2], "timeoutMilliseconds": 60000})
		if err != nil {
			return err
		}
		defer response.Body.Close()
		if response.StatusCode >= 400 {
			return peerFailure(response)
		}
		const limit = 64 << 10
		body, err := io.ReadAll(io.LimitReader(response.Body, limit+1))
		if err != nil {
			return failure(exitPeerError, "bad-response", "provider update：读回复失败: %v", err)
		}
		if len(body) > limit {
			return failure(exitPeerError, "bad-response", "provider update：回复超过 %d 字节", limit)
		}
		var outcome providerUpdateOutcome
		if err := json.Unmarshal(body, &outcome); err != nil {
			return failure(exitPeerError, "bad-response", "provider update：回复不是 JSON: %v", err)
		}
		return reportProviderUpdate(s.out, map[string]string{"proxy": "节点集", "rule": "规则集"}[args[1]]+" "+args[2], outcome, json.RawMessage(body))
	case "test":
		if len(args) < 2 {
			return usage("clash-cli provider test <节点集>")
		}
		client := *s.client
		client.Timeout = 60 * time.Second
		response, err := s.request(context.Background(), &client, http.MethodGet, "/providers/proxies/"+pathEscape(args[1])+"/healthcheck", nil, nil)
		if err != nil {
			return err
		}
		response.Body.Close()
		if response.StatusCode >= 400 {
			return peerFailure(response)
		}
		var set struct {
			Proxies []proxyEntry `json:"proxies"`
		}
		if err := s.call(http.MethodGet, "/providers/proxies/"+pathEscape(args[1]), nil, nil, &set); err != nil {
			return err
		}
		delays := map[string]any{}
		for _, member := range set.Proxies {
			if n := len(member.History); n > 0 && member.History[n-1].Delay > 0 {
				delays[member.Name] = member.History[n-1].Delay
			} else {
				delays[member.Name] = nil
			}
		}
		s.out.succeed(map[string]any{"provider": args[1], "delays": delays}, func() {
			s.out.printf("%s 成员 %d 个：\n", args[1], len(set.Proxies))
			for _, member := range set.Proxies {
				if delay, ok := delays[member.Name].(int); ok {
					s.out.printf("  %s %6dms\n", padRight(member.Name, 40), delay)
				} else {
					s.out.printf("  %s   超时/失败\n", padRight(member.Name, 40))
				}
			}
		})
		return nil
	}
	return usage("clash-cli provider list | update proxy|rule <名称> | test <节点集>")
}

type connection struct {
	ID          string            `json:"id"`
	Metadata    map[string]any    `json:"metadata"`
	Upload      int64             `json:"upload"`
	Download    int64             `json:"download"`
	Chains      []string          `json:"chains"`
	Rule        string            `json:"rule"`
	RulePayload string            `json:"rulePayload"`
	Extra       map[string]string `json:"-"`
}

func connectionHost(c connection) string {
	for _, key := range []string{"host", "destinationIP", "processPath"} {
		if value, _ := c.Metadata[key].(string); value != "" {
			return value
		}
	}
	return "?"
}

func connectionChain(c connection) string {
	chain := slices.Clone(c.Chains)
	slices.Reverse(chain)
	if len(chain) == 0 {
		return "?"
	}
	return strings.Join(chain, " → ")
}

func connectionRule(c connection) string {
	if c.RulePayload != "" {
		return fmt.Sprintf("%s(%s)", c.Rule, c.RulePayload)
	}
	return firstNonEmpty(c.Rule, "-")
}

func cmdConnections(s *session, p parsedArguments) error {
	return listConnections(s, p, p.positional[1:])
}

func listConnections(s *session, p parsedArguments, rest []string) error {
	if p.has("follow") {
		return followConnections(s, p)
	}
	shown := defaultConnectionsShown
	if len(rest) > 0 {
		value, err := strconv.Atoi(rest[0])
		if err != nil || value < 0 {
			return usage("clash-cli connections [N]")
		}
		shown = value
	}
	var reply struct {
		DownloadTotal int64        `json:"downloadTotal"`
		UploadTotal   int64        `json:"uploadTotal"`
		Connections   []connection `json:"connections"`
	}
	if err := s.call(http.MethodGet, "/connections", nil, nil, &reply); err != nil {
		return err
	}
	listed := reply.Connections
	if shown > 0 && len(listed) > shown {
		listed = listed[:shown]
	}
	s.out.succeed(map[string]any{"downloadTotal": reply.DownloadTotal, "uploadTotal": reply.UploadTotal,
		"count": len(reply.Connections), "connections": listed}, func() {
		s.out.printf("活跃连接 %d 个（总 ↓%s ↑%s）：\n", len(reply.Connections), formatBytes(float64(reply.DownloadTotal)), formatBytes(float64(reply.UploadTotal)))
		for _, c := range listed {
			s.out.printf("  %s → %s [%s]  ↑%s ↓%s  %s\n", padRight(connectionHost(c), 35), connectionChain(c), connectionRule(c),
				formatBytes(float64(c.Upload)), formatBytes(float64(c.Download)), s.out.dim(c.ID))
		}
	})
	return nil
}

func followConnections(s *session, p parsedArguments) error {
	if err := s.require("connection-events-v1"); err != nil {
		return err
	}
	ctx, cancel := s.streamContext(p, nil)
	defer cancel()
	return s.follow(ctx, "/clash/v1/connections/events", nil, func(line json.RawMessage) error {
		var batch struct {
			Reset  bool `json:"reset"`
			Events []struct {
				Type       string          `json:"type"`
				ID         string          `json:"id"`
				Connection json.RawMessage `json:"connection"`
			} `json:"events"`
		}
		if err := json.Unmarshal(line, &batch); err != nil {
			return nil
		}
		s.out.emit(line, func() {
			for _, event := range batch.Events {
				switch event.Type {
				case "new":
					var c connection
					_ = json.Unmarshal(event.Connection, &c)
					s.out.printf("+ %s → %s [%s]  %s\n", padRight(connectionHost(c), 35), connectionChain(c), connectionRule(c), s.out.dim(event.ID))
				case "closed":
					s.out.printf("- %s\n", s.out.dim(event.ID))
				}
			}
		})
		return nil
	})
}

func cmdConn(s *session, p parsedArguments) error {
	args := p.positional[1:]
	if len(args) == 0 {
		return usage("clash-cli conn list [N] [-f] | conn close <id|all>")
	}
	switch args[0] {
	case "list":
		return listConnections(s, p, args[1:])
	case "close":
		all := p.has("all") || (len(args) > 1 && args[1] == "all")
		if !all && len(args) < 2 {
			return usage("clash-cli conn close <id|all>")
		}
		s.announce()
		if all {
			if err := s.call(http.MethodDelete, "/connections", nil, nil, nil); err != nil {
				return err
			}
			s.out.succeed(nil, func() { s.out.printf("✓ 已关闭所有连接\n") })
			return nil
		}
		var current struct {
			Connections []connection `json:"connections"`
		}
		if err := s.call(http.MethodGet, "/connections", nil, nil, &current); err != nil {
			return err
		}
		found := false
		for _, c := range current.Connections {
			found = found || c.ID == args[1]
		}
		if !found {
			return failure(exitPeerError, "no-such-connection", "没有这条连接：%s（clash-cli connections 列出当前连接；它可能已经结束）", args[1])
		}
		if err := s.call(http.MethodDelete, "/connections/"+pathEscape(args[1]), nil, nil, nil); err != nil {
			return err
		}
		s.out.succeed(nil, func() { s.out.printf("✓ 已关闭连接 %s\n", args[1]) })
		return nil
	}
	return usage("clash-cli conn list [N] [-f] | conn close <id|all>")
}

func (s *session) streamContext(p parsedArguments, seconds *int) (context.Context, context.CancelFunc) {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	duration := time.Duration(0)
	switch {
	case seconds != nil:
		duration = time.Duration(*seconds)*time.Second + 500*time.Millisecond
	case p.has("follow"):
	case !s.env.color:
		duration = defaultStreamSeconds * time.Second
	}
	if duration <= 0 {
		return ctx, stop
	}
	timed, cancel := context.WithTimeout(ctx, duration)
	return timed, func() { cancel(); stop() }
}

func secondsArgument(args []string, command string) (*int, []string, error) {
	if len(args) == 0 {
		return nil, args, nil
	}
	value, err := strconv.Atoi(args[0])
	if err != nil {
		return nil, args, nil
	}
	if value <= 0 {
		return nil, nil, usage("clash-cli %s [秒数]：秒数是正整数", command)
	}
	return &value, args[1:], nil
}

func cmdTraffic(s *session, p parsedArguments) error {
	seconds, _, err := secondsArgument(p.positional[1:], "traffic")
	if err != nil {
		return err
	}
	ctx, cancel := s.streamContext(p, seconds)
	defer cancel()
	if !s.out.json {
		if seconds != nil {
			s.out.printf("实时流量（%d秒）：\n", *seconds)
		} else {
			s.out.printf("实时流量：\n")
		}
	}
	return s.follow(ctx, "/traffic", nil, func(line json.RawMessage) error {
		var frame struct {
			Up, Down, UpTotal, DownTotal float64
		}
		_ = json.Unmarshal(line, &frame)
		s.out.emit(line, func() {
			s.out.printf("  ↑ %10s  ↓ %10s  | 累计 ↑%s ↓%s\n", formatRate(frame.Up), formatRate(frame.Down), formatBytes(frame.UpTotal), formatBytes(frame.DownTotal))
		})
		return nil
	})
}

var logArrivalClock = time.Now

func cmdLogs(s *session, p parsedArguments) error {
	seconds, rest, err := secondsArgument(p.positional[1:], "logs")
	if err != nil {
		return err
	}
	level := firstNonEmpty(p.flags["level"], "info")
	if len(rest) > 0 {
		level = rest[0]
	}
	switch level {
	case "debug", "info", "warning", "error", "silent":
	default:
		return usage("clash-cli logs [秒数] [debug|info|warning|error]")
	}
	ctx, cancel := s.streamContext(p, seconds)
	defer cancel()
	if !s.out.json {
		if seconds != nil {
			s.out.printf("日志（%d秒，level=%s）：\n", *seconds, level)
		} else {
			s.out.printf("日志（level=%s）：\n", level)
		}
	}
	return s.follow(ctx, "/logs", url.Values{"level": {level}}, func(line json.RawMessage) error {
		var frame struct {
			Type    string `json:"type"`
			Payload string `json:"payload"`
		}
		_ = json.Unmarshal(line, &frame)
		arrived := logArrivalClock().Format(time.TimeOnly)
		s.out.emit(line, func() { s.out.printf("  %s [%s] %s\n", arrived, frame.Type, frame.Payload) })
		return nil
	})
}

func cmdRules(s *session, p parsedArguments) error {
	return listRules(s, p.positional[1:])
}

func listRules(s *session, rest []string) error {
	shown := defaultRulesShown
	if len(rest) > 0 {
		value, err := strconv.Atoi(rest[0])
		if err != nil || value < 0 {
			return usage("clash-cli rules [N]（0 = 全部）")
		}
		shown = value
	}
	var reply struct {
		Rules []map[string]any `json:"rules"`
	}
	if err := s.call(http.MethodGet, "/rules", nil, nil, &reply); err != nil {
		return err
	}
	listed := reply.Rules
	if shown > 0 && len(listed) > shown {
		listed = listed[:shown]
	}
	s.out.succeed(map[string]any{"count": len(reply.Rules), "rules": listed}, func() {
		s.out.printf("规则 %d 条：\n", len(reply.Rules))
		for _, rule := range listed {
			payload := fmt.Sprint(rule["payload"])
			if payload == "" {
				payload = "-"
			}
			s.out.printf("  %s %s → %v\n", padRight(fmt.Sprint(rule["type"]), 20), padRight(payload, 30), rule["proxy"])
		}
	})
	return nil
}

func cmdRule(s *session, p parsedArguments) error {
	args := p.positional[1:]
	if len(args) == 0 {
		return usage("clash-cli rule list [N] | rule match <域名|IP|URL> [port=N] [network=tcp|udp] [src=IP[:端口]] [process=名称] [--resolve]")
	}
	switch args[0] {
	case "list":
		return listRules(s, args[1:])
	case "match":
		if len(args) < 2 {
			return usage("clash-cli rule match <域名|IP|URL> [port=N] [network=tcp|udp] [src=IP[:端口]] [process=名称] [--resolve]")
		}
		return ruleMatch(s, args[1], args[2:], p.has("resolve"))
	}
	return usage("clash-cli rule list [N] | rule match <域名|IP|URL> ...")
}

func ruleMatchQuery(target string, pairs []string, resolve bool) (url.Values, error) {
	query := url.Values{}
	host, port := target, ""
	if strings.Contains(target, "://") {
		parsed, err := url.Parse(target)
		if err != nil || parsed.Hostname() == "" {
			return nil, usage("clash-cli rule match：%q 不是 URL", target)
		}
		host, port = parsed.Hostname(), parsed.Port()
		if port == "" {
			port = map[string]string{"http": "80", "https": "443", "ws": "80", "wss": "443"}[strings.ToLower(parsed.Scheme)]
		}
	} else if h, p, err := net.SplitHostPort(target); err == nil {
		host, port = h, p
	}
	if net.ParseIP(strings.Trim(host, "[]")) != nil {
		query.Set("ip", strings.Trim(host, "[]"))
	} else {
		query.Set("host", host)
	}
	if port != "" {
		query.Set("port", port)
	}
	for _, pair := range pairs {
		key, value, ok := strings.Cut(pair, "=")
		if !ok || value == "" {
			return nil, usage("clash-cli rule match：参数写成 key=value（port、network、src、process），收到 %q", pair)
		}
		switch key {
		case "port", "network", "src", "process":
			query.Set(key, value)
		default:
			return nil, usage("clash-cli rule match：不认识的参数 %q（port、network、src、process）", key)
		}
	}
	if resolve {
		query.Set("resolve", "1")
	}
	return query, nil
}

type ruleMatchRule struct {
	Index    int            `json:"index"`
	Type     string         `json:"type"`
	Payload  string         `json:"payload"`
	SubRules string         `json:"subRules"`
	Through  *ruleMatchRule `json:"through"`
}

func (r *ruleMatchRule) describe() string {
	text := fmt.Sprintf("#%d %s", r.Index, r.Type)
	if r.Payload != "" {
		text += "(" + r.Payload + ")"
	}
	if r.SubRules != "" {
		text += "（子规则集 " + r.SubRules + "）"
	}
	return text
}

var assumedText = map[string]string{
	"src-port=0":           "来源端口按 0",
	"inbound=tun":          "入站按隧道（tun）",
	"process-path=unknown": "进程路径未知（PROCESS-PATH 规则按不命中）",
	"uid=unknown":          "UID 未知（UID 规则按不命中）",
}

func ruleMatch(s *session, target string, pairs []string, resolve bool) error {
	if err := s.require("rules-match-v1"); err != nil {
		return err
	}
	query, err := ruleMatchQuery(target, pairs, resolve)
	if err != nil {
		return err
	}
	var raw map[string]any
	if err := s.call(http.MethodGet, "/clash/v1/rules/match", query, nil, &raw); err != nil {
		return err
	}
	var reply struct {
		Mode        string         `json:"mode"`
		Host        string         `json:"host"`
		FakeIP      bool           `json:"fakeIP"`
		HostsIP     string         `json:"hostsIP"`
		ResolvedIP  string         `json:"resolvedIP"`
		Assumed     []string       `json:"assumed"`
		Decided     bool           `json:"decided"`
		Missing     []string       `json:"missing"`
		Rule        *ruleMatchRule `json:"rule"`
		Proxy       string         `json:"proxy"`
		Chain       []string       `json:"chain"`
		Conditional bool           `json:"conditional"`
		Dropped     bool           `json:"dropped"`
		Notes       []string       `json:"notes"`
		Error       string         `json:"error"`
	}
	encoded, _ := json.Marshal(raw)
	_ = json.Unmarshal(encoded, &reply)
	s.out.succeed(raw, func() {
		subject := firstNonEmpty(query.Get("host"), query.Get("ip"))
		if reply.FakeIP && reply.Host != "" {
			subject += "（fake-ip → " + reply.Host + "）"
		} else if reply.Host != "" && reply.Host != subject {
			subject += "（→ " + reply.Host + "）"
		}
		if reply.Dropped {
			s.out.printf("%s：隧道按 IP 版本策略直接丢弃这条连接，不走任何规则\n", subject)
			return
		}
		s.out.printf("%s (%s) → %s\n", subject, firstNonEmpty(query.Get("network"), "tcp"), strings.Join(reply.Chain, " → "))
		switch {
		case reply.Mode != "rule":
			s.out.printf("模式 %s：不看规则\n", reply.Mode)
		case reply.Rule != nil:
			s.out.printf("命中规则 %s\n", reply.Rule.describe())
			for through := reply.Rule.Through; through != nil; through = through.Through {
				s.out.printf("  经由 %s\n", through.describe())
			}
		default:
			s.out.printf("没有规则命中，走 DIRECT\n")
		}
		if !reply.Decided {
			s.out.printf("未定：前面有规则需要下面的信息，结果可能不同\n")
		}
		for _, missing := range reply.Missing {
			switch missing {
			case "ip":
				s.out.printf("  · IP 类规则需要解析域名，这次没解析（加 --resolve 解析）\n")
			case "process":
				s.out.printf("  · PROCESS 规则需要进程，这次没给（process=名称或路径）\n")
			}
		}
		if reply.HostsIP != "" {
			s.out.printf("  · hosts 把它指到 %s\n", reply.HostsIP)
		}
		if reply.ResolvedIP != "" {
			s.out.printf("  · 解析得到 %s\n", reply.ResolvedIP)
		}
		var assumptions []string
		for _, item := range reply.Assumed {
			if text, ok := assumedText[item]; ok {
				assumptions = append(assumptions, text)
				continue
			}
			key, value, _ := strings.Cut(item, "=")
			switch key {
			case "port":
				assumptions = append(assumptions, "端口按 "+value)
			case "src":
				assumptions = append(assumptions, "来源按本机隧道地址 "+value)
			default:
				assumptions = append(assumptions, item)
			}
		}
		if len(assumptions) > 0 {
			s.out.printf("  · 假设：%s\n", strings.Join(assumptions, "；"))
		}
		for _, note := range reply.Notes {
			switch {
			case strings.HasPrefix(note, "this device does not name the process"):
				s.out.printf("  · 这台设备拿不到连接的进程名，PROCESS 规则在这里永远不命中\n")
			case strings.HasPrefix(note, "the chain is the groups' current choice"):
				s.out.printf("  · 链路是各组当前的选择，之后可能变化\n")
			}
		}
		if reply.Error != "" {
			s.out.printf("  · %s\n", reply.Error)
		}
	})
	return nil
}

func cmdDNS(s *session, p parsedArguments) error {
	args := p.positional[1:]
	if len(args) < 2 || (args[0] != "query" && args[0] != "explain") {
		return usage("clash-cli dns query <域名> [type] | dns explain <域名> [type]")
	}
	recordType := "A"
	if len(args) > 2 {
		recordType = args[2]
	}
	var reply map[string]any
	if args[0] == "query" {
		if err := s.call(http.MethodGet, "/dns/query", url.Values{"name": {args[1]}, "type": {recordType}}, nil, &reply); err != nil {
			return err
		}
	} else {
		if err := s.require("dns-explain-v1"); err != nil {
			return err
		}
		if err := s.call(http.MethodGet, "/clash/v1/dns/explain", url.Values{"domain": {args[1]}, "type": {recordType}}, nil, &reply); err != nil {
			return err
		}
	}
	if args[0] == "query" {
		s.out.succeed(reply, func() { printDNSAnswer(s.out, args[1], recordType, reply) })
	} else {
		s.out.succeed(reply, func() { printDNSExplanation(s.out, reply) })
	}
	return nil
}

func printDNSAnswer(out *output, name, recordType string, reply map[string]any) {
	answers, _ := reply["Answer"].([]any)
	if len(answers) == 0 {
		status, _ := reply["Status"].(float64)
		out.printf("%s %s：没有记录（rcode %d）\n", name, strings.ToUpper(recordType), int(status))
		return
	}
	out.printf("%s %s：\n", name, strings.ToUpper(recordType))
	for _, item := range answers {
		record, _ := item.(map[string]any)
		ttl, _ := record["TTL"].(float64)
		out.printf("  %s  %s  TTL %d  %v\n", record["name"], dnsTypeName(record["type"]), int(ttl), record["data"])
	}
}

var dnsTypeNames = map[int]string{1: "A", 2: "NS", 5: "CNAME", 6: "SOA", 12: "PTR", 15: "MX", 16: "TXT", 28: "AAAA", 33: "SRV", 64: "SVCB", 65: "HTTPS"}

func dnsTypeName(value any) string {
	if number, ok := value.(float64); ok {
		if name, known := dnsTypeNames[int(number)]; known {
			return name
		}
		return fmt.Sprintf("TYPE%d", int(number))
	}
	return fmt.Sprint(value)
}

func printDNSExplanation(out *output, reply map[string]any) {
	out.printf("%v %v：走 %v", reply["domain"], reply["type"], reply["source"])
	if rule, _ := reply["matchedRule"].(string); rule != "" {
		out.printf("（命中 %s）", rule)
	}
	out.printf("\n")
	if candidates, _ := reply["candidates"].([]any); len(candidates) > 0 {
		out.printf("  候选解析器：\n")
		for _, candidate := range candidates {
			out.printf("    %v\n", candidate)
		}
	}
	if cache, _ := reply["cache"].(map[string]any); cache != nil {
		if hit, _ := cache["hit"].(bool); hit {
			stale, _ := cache["stale"].(bool)
			state := "有效"
			if stale {
				state = "已过期，仍在用并在后台刷新"
			}
			out.printf("  缓存：命中，到期 %v（%s）\n", cache["expiresAt"], state)
		} else {
			out.printf("  缓存：未命中\n")
		}
	}
	if answered, _ := reply["answeredBy"].(string); answered != "" {
		out.printf("  实际查询由 %s 回答：%v\n", answered, reply["answer"])
	}
}

func cmdFlush(s *session, p parsedArguments) error {
	args := p.positional[1:]
	if len(args) != 1 || (args[0] != "fakeip" && args[0] != "dns") {
		return usage("clash-cli flush fakeip|dns")
	}
	s.announce()
	path := map[string]string{"fakeip": "/cache/fakeip/flush", "dns": "/cache/dns/flush"}[args[0]]
	if err := s.call(http.MethodPost, path, nil, nil, nil); err != nil {
		return err
	}
	s.out.succeed(nil, func() {
		if args[0] == "fakeip" {
			s.out.printf("✓ 已清空 fake-ip 池（App 手里的旧假 IP 会失效，相关连接可能要重连）\n")
		} else {
			s.out.printf("✓ 已清空 DNS 缓存\n")
		}
	})
	return nil
}

type providerUpdateOutcome struct {
	Result        string `json:"result"`
	CountBefore   int    `json:"countBefore"`
	CountAfter    int    `json:"countAfter"`
	Error         string `json:"error,omitempty"`
	PendingReason string `json:"pendingReason,omitempty"`
	CheckedAt     int64  `json:"checkedAt,omitempty"`
}

func reportProviderUpdate(out *output, what string, outcome providerUpdateOutcome, answer json.RawMessage) error {
	switch outcome.Result {
	case "updated", "unchanged", "pendingApp", "failed":
	default:
		return failure(exitPeerError, "bad-response", "provider update：回复里的结果不认识：%q", outcome.Result)
	}
	if outcome.Result == "failed" {
		reason := outcome.Error
		if reason == "" {
			reason = "检查失败"
		}
		return failure(exitPeerError, "provider-update-failed", "%s：%s", what, reason)
	}
	checked := ""
	if outcome.CheckedAt > 0 {
		checked = "，检查于 " + time.Unix(outcome.CheckedAt, 0).Format("2006-01-02 15:04:05")
	}
	out.succeed(answer, func() {
		switch outcome.Result {
		case "updated":
			out.printf("✓ 已更新 %s（%d → %d 条%s）\n", what, outcome.CountBefore, outcome.CountAfter, checked)
		case "unchanged":
			out.printf("✓ 没有变化 %s（%d 条%s）\n", what, outcome.CountAfter, checked)
		case "pendingApp":
			out.printf("%s：打开 Clash 后生效\n", what)
		}
	})
	return nil
}
