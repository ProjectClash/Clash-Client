package main

import (
	"strconv"
	"strings"
	"time"
)

type parsedArguments struct {
	positional []string
	flags      map[string]string
}

func (p parsedArguments) has(name string) bool { return p.flags[name] != "" }

var (
	globalValueOptions  = map[string]string{"u": "url", "url": "url", "secret": "secret", "fingerprint": "fingerprint", "timeout": "timeout", "socket": "socket"}
	globalBoolOptions   = map[string]string{"json": "json", "secret-stdin": "secret-stdin"}
	commandValueOptions = map[string]string{"level": "level", "test-url": "test-url", "delay-timeout": "delay-timeout",
		"geodata-dir": "geodata-dir", "interval": "interval", "profile": "profile"}
	commandBoolOptions = map[string]string{"f": "follow", "follow": "follow", "resolve": "resolve", "all": "all",
		"fake-ip-filter": "fake-ip-filter", "h": "help", "help": "help"}
)

func parseArguments(args []string, options *globalOptions) (parsedArguments, error) {
	parsed := parsedArguments{flags: map[string]string{}}
	for i := 0; i < len(args); i++ {
		arg := args[i]
		if arg == "--" {
			parsed.positional = append(parsed.positional, args[i+1:]...)
			break
		}
		if arg == "-" || !strings.HasPrefix(arg, "-") {
			parsed.positional = append(parsed.positional, arg)
			continue
		}
		name := strings.TrimLeft(arg, "-")
		value, hasValue := "", false
		if index := strings.IndexByte(name, '='); index >= 0 {
			name, value, hasValue = name[:index], name[index+1:], true
		}
		takeValue := func() (string, error) {
			if hasValue {
				return value, nil
			}
			if i+1 >= len(args) {
				return "", failure(exitUsage, "usage", "option %s needs a value", arg)
			}
			i++
			return args[i], nil
		}
		switch {
		case globalValueOptions[name] != "":
			v, err := takeValue()
			if err != nil {
				return parsed, err
			}
			switch globalValueOptions[name] {
			case "url":
				options.url = v
			case "secret":
				options.secret = v
			case "fingerprint":
				options.fingerprint = v
			case "socket":
				options.socket = v
			case "timeout":
				timeout, err := parseTimeout(v)
				if err != nil {
					return parsed, err
				}
				options.timeout = timeout
			}
		case globalBoolOptions[name] != "":
			if hasValue {
				return parsed, failure(exitUsage, "usage", "option --%s takes no value", name)
			}
			switch globalBoolOptions[name] {
			case "json":
				options.json = true
			case "secret-stdin":
				options.secretStdin = true
			}
		case commandValueOptions[name] != "":
			v, err := takeValue()
			if err != nil {
				return parsed, err
			}
			parsed.flags[commandValueOptions[name]] = v
		case commandBoolOptions[name] != "":
			if hasValue {
				return parsed, failure(exitUsage, "usage", "option %s takes no value", arg)
			}
			parsed.flags[commandBoolOptions[name]] = "1"
		default:
			return parsed, failure(exitUsage, "usage", "unknown option %s", arg)
		}
	}
	return parsed, nil
}

func parseTimeout(text string) (time.Duration, error) {
	if seconds, err := strconv.ParseFloat(text, 64); err == nil && seconds > 0 {
		return time.Duration(seconds * float64(time.Second)), nil
	}
	duration, err := time.ParseDuration(text)
	if err != nil || duration <= 0 {
		return 0, failure(exitUsage, "usage", "--timeout %q is not a positive duration", text)
	}
	return duration, nil
}
