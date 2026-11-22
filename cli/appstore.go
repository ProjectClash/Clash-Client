package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"slices"
	"sort"
	"strings"
)

// The App keeps its configuration library (store/profiles.json) as the source of
// truth and rebuilds the derived files on connect. These commands only edit the
// inputs (appendRules/prependRules and the DNS policy inside the runtime patch),
// so they never race with the App's generator: changes apply on the next connect.

const (
	appStoreCapability = "app-store-v1"
	appStoreRoot       = "/clash/v1/app"
	appStoreEffective  = "next-connect"
	appStoreNote       = "改动在下次连接生效（现在连着的连接仍按旧规则）"
)

type appProfileActive struct {
	ProfileID string `json:"profileID"`
	Revision  string `json:"revision"`
}

type appProfile struct {
	ID             string `json:"id"`
	Label          string `json:"label"`
	Order          int    `json:"order"`
	ActiveRevision string `json:"activeRevision"`
	Active         bool   `json:"active"`
	AppendedRules  int    `json:"appendedRules"`
	PrependedRules bool   `json:"prependedRules"`
	Patched        bool   `json:"patched"`
}

type appProfilesIndex struct {
	Active   appProfileActive `json:"active"`
	Profiles []appProfile     `json:"profiles"`
}

type appProfileRules struct {
	ID           string   `json:"id"`
	PrependRules bool     `json:"prependRules"`
	AppendRules  []string `json:"appendRules"`
	PatchJSON    string   `json:"patchJSON"`
}

type appDNSPolicy struct {
	NameserverPolicy map[string][]string `json:"nameserverPolicy"`
	FakeIPFilter     []string            `json:"fakeIPFilter"`
}

// appDNSPolicyWrite leaves a nil field out of the request, which the controller
// reads as "keep this part as it is".
type appDNSPolicyWrite struct {
	NameserverPolicy *map[string][]string `json:"nameserverPolicy,omitempty"`
	FakeIPFilter     *[]string            `json:"fakeIPFilter,omitempty"`
}

type appRulesResult struct {
	ProfileID   string   `json:"profileID"`
	Label       string   `json:"label,omitempty"`
	Added       int      `json:"added"`
	Removed     int      `json:"removed,omitempty"`
	Count       int      `json:"count"`
	AppendRules []string `json:"appendRules"`
	Effective   string   `json:"effective"`
}

type appDNSPolicyResult struct {
	ProfileID        string              `json:"profileID"`
	Label            string              `json:"label,omitempty"`
	NameserverPolicy map[string][]string `json:"nameserverPolicy,omitempty"`
	FakeIPFilter     []string            `json:"fakeIPFilter,omitempty"`
	Cleared          string              `json:"cleared,omitempty"`
	Effective        string              `json:"effective"`
}

func (s *session) requireAppStore() error {
	if slices.Contains(s.caps.Capabilities, appStoreCapability) {
		return nil
	}
	return failure(exitUnsupported, "unsupported",
		"这个 Clash App（内核 %s）还不支持 App 配置读写（%s），请更新 App", s.caps.CoreVersion, appStoreCapability)
}

func appProfilePath(id, suffix string) string {
	return appStoreRoot + "/profiles/" + pathEscape(id) + "/" + suffix
}

func appProfileTitle(profile appProfile) string {
	switch {
	case profile.Label != "" && profile.ID != "":
		return fmt.Sprintf("%s（%s）", profile.Label, profile.ID)
	case profile.Label != "":
		return profile.Label
	case profile.ID != "":
		return profile.ID
	}
	return "未命名的配置"
}

func (s *session) appProfiles() (appProfilesIndex, json.RawMessage, error) {
	var index appProfilesIndex
	var raw json.RawMessage
	if err := s.call(http.MethodGet, appStoreRoot+"/profiles", nil, nil, &raw); err != nil {
		return index, nil, err
	}
	if err := json.Unmarshal(raw, &index); err != nil {
		return index, raw, failure(exitPeerError, "bad-response", "配置列表不是 JSON: %v", err)
	}
	return index, raw, nil
}

func (s *session) resolveAppProfile(name string) (appProfile, error) {
	index, _, err := s.appProfiles()
	if err != nil {
		return appProfile{}, err
	}
	if name == "" {
		if index.Active.ProfileID == "" {
			return appProfile{}, failure(exitPeerError, "bad-response", "控制器没有说哪个配置是当前配置（clash-cli profiles 查看）")
		}
		for _, profile := range index.Profiles {
			if profile.ID == index.Active.ProfileID {
				return profile, nil
			}
		}
		return appProfile{ID: index.Active.ProfileID, Active: true, ActiveRevision: index.Active.Revision}, nil
	}
	for _, profile := range index.Profiles {
		if profile.ID == name {
			return profile, nil
		}
	}
	var matches []appProfile
	for _, profile := range index.Profiles {
		if profile.Label == name {
			matches = append(matches, profile)
		}
	}
	switch len(matches) {
	case 1:
		return matches[0], nil
	case 0:
		return appProfile{}, usage("clash-cli --profile %q：没有这个配置（clash-cli profiles 查看现有配置）", name)
	}
	return appProfile{}, usage("clash-cli --profile %q：有 %d 个同名配置，请改用 id（clash-cli profiles 查看）", name, len(matches))
}

func (s *session) appRules(id string) (appProfileRules, json.RawMessage, error) {
	var rules appProfileRules
	var raw json.RawMessage
	if err := s.call(http.MethodGet, appProfilePath(id, "rules"), nil, nil, &raw); err != nil {
		return rules, nil, err
	}
	if err := json.Unmarshal(raw, &rules); err != nil {
		return rules, raw, failure(exitPeerError, "bad-response", "%s 的规则不是 JSON: %v", id, err)
	}
	if rules.AppendRules == nil {
		rules.AppendRules = []string{}
	}
	return rules, raw, nil
}

func (s *session) writeAppRules(id string, prepend bool, appendRules []string) error {
	if appendRules == nil {
		appendRules = []string{}
	}
	return s.call(http.MethodPut, appProfilePath(id, "rules"), nil, struct {
		PrependRules bool     `json:"prependRules"`
		AppendRules  []string `json:"appendRules"`
	}{prepend, appendRules}, nil)
}

func (s *session) appDNSPolicy(id string) (appDNSPolicy, json.RawMessage, error) {
	var policy appDNSPolicy
	var raw json.RawMessage
	if err := s.call(http.MethodGet, appProfilePath(id, "dns-policy"), nil, nil, &raw); err != nil {
		return policy, nil, err
	}
	if err := json.Unmarshal(raw, &policy); err != nil {
		return policy, raw, failure(exitPeerError, "bad-response", "%s 的 DNS 策略不是 JSON: %v", id, err)
	}
	return policy, raw, nil
}

func (s *session) writeAppDNSPolicy(id string, policy appDNSPolicyWrite) error {
	return s.call(http.MethodPut, appProfilePath(id, "dns-policy"), nil, policy, nil)
}

func cmdAppProfiles(s *session, p parsedArguments) error {
	if len(p.positional) > 1 {
		return usage("clash-cli profiles")
	}
	if err := s.requireAppStore(); err != nil {
		return err
	}
	index, raw, err := s.appProfiles()
	if err != nil {
		return err
	}
	s.out.succeed(raw, func() { printAppProfiles(s.out, index) })
	return nil
}

func printAppProfiles(out *output, index appProfilesIndex) {
	if len(index.Profiles) == 0 {
		out.printf("App 里还没有配置\n")
		return
	}
	var rows [][]string
	for _, profile := range index.Profiles {
		marker := ""
		if profile.Active || profile.ID == index.Active.ProfileID {
			marker = "*"
		}
		revision := profile.ActiveRevision
		if revision == "" {
			revision = "-"
		}
		label := profile.Label
		if label == "" {
			label = "-"
		}
		rows = append(rows, []string{marker, label, profile.ID, revision, fmt.Sprint(profile.AppendedRules)})
	}
	out.table([]string{"当前", "名称", "id", "修订", "追加规则"}, rows)
}

// cmdRulesEdit handles `rules append|remove`, which edits the App's configuration
// instead of the running rule list.
func cmdRulesEdit(s *session, p parsedArguments, verb string, rules []string) error {
	if len(rules) == 0 {
		return usage("clash-cli rules %s <规则>... [--profile <id|名称>]", verb)
	}
	for _, rule := range rules {
		if strings.TrimSpace(rule) == "" {
			return usage("clash-cli rules %s：规则不能是空的", verb)
		}
	}
	if err := s.requireAppStore(); err != nil {
		return err
	}
	profile, err := s.resolveAppProfile(p.flags["profile"])
	if err != nil {
		return err
	}
	current, _, err := s.appRules(profile.ID)
	if err != nil {
		return err
	}
	var merged []string
	added, removed := 0, 0
	switch verb {
	case "append":
		merged, added = mergeAppendRules(current.AppendRules, rules)
	case "remove":
		merged, removed = removeAppendRules(current.AppendRules, rules)
	}
	result := appRulesResult{
		ProfileID: profile.ID, Label: profile.Label, Added: added, Removed: removed,
		Count: len(merged), AppendRules: merged, Effective: appStoreEffective,
	}
	if added == 0 && removed == 0 {
		s.out.succeed(result, func() {
			s.out.printf("%s的追加规则没有变化（现有 %d 条）\n", appProfileTitle(profile), len(merged))
		})
		return nil
	}
	s.announce()
	if err := s.writeAppRules(profile.ID, current.PrependRules, merged); err != nil {
		return err
	}
	s.out.succeed(result, func() {
		switch verb {
		case "append":
			s.out.printf("✓ %s追加 %d 条规则，现在共 %d 条\n", appProfileTitle(profile), added, len(merged))
			if skipped := len(rules) - added; skipped > 0 {
				s.out.printf("  · 其中 %d 条本来就有，没有重复追加\n", skipped)
			}
		case "remove":
			s.out.printf("✓ %s移除 %d 条规则，现在共 %d 条\n", appProfileTitle(profile), removed, len(merged))
		}
		s.out.printf("  · %s\n", appStoreNote)
	})
	return nil
}

// mergeAppendRules appends the rules that are missing, keeping the existing order
// and dropping duplicates from both the existing list and the arguments.
func mergeAppendRules(existing, added []string) ([]string, int) {
	merged := make([]string, 0, len(existing)+len(added))
	seen := make(map[string]bool, len(existing)+len(added))
	for _, rule := range existing {
		if seen[rule] {
			continue
		}
		seen[rule] = true
		merged = append(merged, rule)
	}
	appended := 0
	for _, rule := range added {
		if seen[rule] {
			continue
		}
		seen[rule] = true
		merged = append(merged, rule)
		appended++
	}
	return merged, appended
}

func removeAppendRules(existing, removed []string) ([]string, int) {
	drop := make(map[string]bool, len(removed))
	for _, rule := range removed {
		drop[rule] = true
	}
	kept := make([]string, 0, len(existing))
	for _, rule := range existing {
		if drop[rule] {
			continue
		}
		kept = append(kept, rule)
	}
	return kept, len(existing) - len(kept)
}

func cmdDNSPolicy(s *session, p parsedArguments) error {
	args := p.positional[2:]
	if len(args) == 0 {
		return dnsPolicyShow(s, p)
	}
	switch args[0] {
	case "set":
		return dnsPolicySet(s, p, args[1:])
	case "clear":
		return dnsPolicyClear(s, p, args[1:])
	}
	return usage("clash-cli dns policy | dns policy set '+.域名=地址[,地址]'... | dns policy clear [--fake-ip-filter]")
}

func dnsPolicyShow(s *session, p parsedArguments) error {
	if err := s.requireAppStore(); err != nil {
		return err
	}
	profile, err := s.resolveAppProfile(p.flags["profile"])
	if err != nil {
		return err
	}
	policy, raw, err := s.appDNSPolicy(profile.ID)
	if err != nil {
		return err
	}
	s.out.succeed(raw, func() {
		s.out.printf("DNS 策略：%s\n", appProfileTitle(profile))
		printNameserverPolicy(s.out, policy.NameserverPolicy, "  ")
		printFakeIPFilter(s.out, policy.FakeIPFilter, "  ")
	})
	return nil
}

func dnsPolicySet(s *session, p parsedArguments, pairs []string) error {
	if len(pairs) == 0 {
		return usage("clash-cli dns policy set '+.域名=地址[,地址]'... [--profile <id|名称>]")
	}
	added, err := parseNameserverPairs(pairs)
	if err != nil {
		return err
	}
	if err := s.requireAppStore(); err != nil {
		return err
	}
	profile, err := s.resolveAppProfile(p.flags["profile"])
	if err != nil {
		return err
	}
	current, _, err := s.appDNSPolicy(profile.ID)
	if err != nil {
		return err
	}
	merged := make(map[string][]string, len(current.NameserverPolicy)+len(added))
	for domain, servers := range current.NameserverPolicy {
		merged[domain] = servers
	}
	for domain, servers := range added {
		merged[domain] = servers
	}
	s.announce()
	if err := s.writeAppDNSPolicy(profile.ID, appDNSPolicyWrite{NameserverPolicy: &merged}); err != nil {
		return err
	}
	result := appDNSPolicyResult{
		ProfileID: profile.ID, Label: profile.Label, NameserverPolicy: merged, Effective: appStoreEffective,
	}
	s.out.succeed(result, func() {
		s.out.printf("✓ %s写入 %d 条 nameserver-policy，现有 %d 条：\n", appProfileTitle(profile), len(added), len(merged))
		for _, domain := range sortedKeys(added) {
			s.out.printf("    %s → %s\n", domain, strings.Join(added[domain], ","))
		}
		s.out.printf("  · %s\n", appStoreNote)
	})
	return nil
}

func dnsPolicyClear(s *session, p parsedArguments, rest []string) error {
	fakeIPFilter := p.has("fake-ip-filter")
	if len(rest) > 0 {
		return usage("clash-cli dns policy clear [--fake-ip-filter] [--profile <id|名称>]")
	}
	if err := s.requireAppStore(); err != nil {
		return err
	}
	profile, err := s.resolveAppProfile(p.flags["profile"])
	if err != nil {
		return err
	}
	write := appDNSPolicyWrite{}
	cleared := "nameserverPolicy"
	result := appDNSPolicyResult{ProfileID: profile.ID, Label: profile.Label, Effective: appStoreEffective}
	if fakeIPFilter {
		empty := []string{}
		write.FakeIPFilter = &empty
		cleared = "fakeIPFilter"
		result.FakeIPFilter = empty
	} else {
		empty := map[string][]string{}
		write.NameserverPolicy = &empty
		cleared = "nameserverPolicy"
	}
	result.Cleared = cleared
	s.announce()
	if err := s.writeAppDNSPolicy(profile.ID, write); err != nil {
		return err
	}
	s.out.succeed(result, func() {
		label := map[string]string{"nameserverPolicy": "nameserver-policy", "fakeIPFilter": "fake-ip-filter"}[cleared]
		s.out.printf("✓ 已清空 %s的 %s\n", appProfileTitle(profile), label)
		s.out.printf("  · %s\n", appStoreNote)
	})
	return nil
}

func parseNameserverPairs(pairs []string) (map[string][]string, error) {
	policy := make(map[string][]string, len(pairs))
	for _, pair := range pairs {
		domain, servers, ok := strings.Cut(pair, "=")
		domain = strings.TrimSpace(domain)
		if !ok || domain == "" || strings.TrimSpace(servers) == "" {
			return nil, usage("clash-cli dns policy set：参数写成 '+.域名=地址[,地址]'，收到 %q", pair)
		}
		var list []string
		for _, server := range strings.Split(servers, ",") {
			server = strings.TrimSpace(server)
			if server == "" {
				return nil, usage("clash-cli dns policy set：%s 的地址里有一个是空的", domain)
			}
			list = append(list, server)
		}
		policy[domain] = append(policy[domain], list...)
	}
	return policy, nil
}

func printNameserverPolicy(out *output, policy map[string][]string, indent string) {
	if len(policy) == 0 {
		out.printf("%snameserver-policy：没有设置\n", indent)
		return
	}
	out.printf("%snameserver-policy（%d 条）：\n", indent, len(policy))
	for _, domain := range sortedKeys(policy) {
		out.printf("%s  %s → %s\n", indent, domain, strings.Join(policy[domain], ","))
	}
}

func printFakeIPFilter(out *output, filter []string, indent string) {
	if len(filter) == 0 {
		out.printf("%sfake-ip-filter：没有设置\n", indent)
		return
	}
	out.printf("%sfake-ip-filter（%d 条）：\n", indent, len(filter))
	for _, item := range filter {
		out.printf("%s  %s\n", indent, item)
	}
}

func sortedKeys[V any](items map[string]V) []string {
	names := make([]string, 0, len(items))
	for name := range items {
		names = append(names, name)
	}
	sort.Strings(names)
	return names
}
