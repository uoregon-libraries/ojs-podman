package main

import (
	"reflect"
	"testing"
)

var testEnv = map[string]string{
	"PLAIN":  "abc123",
	"TRICKY": `a\b"c'd$e{f}#;g`,
	"HOSTS":  `["localhost", "127.0.0.1"]`,
	"SPACE":  "a b",
	"TAB":    "a\tb",
	"VTAB":   "a\vb",
	"LF":     "a\nb",
	"CR":     "a\rb",
	"BLANK":  "",
}

func lookup(name string) (string, bool) {
	var val, ok = testEnv[name]
	return val, ok
}

func TestRender(t *testing.T) {
	var tests = map[string]struct {
		config string
		want   string
	}{
		"unquoted":              {"password = ${PLAIN}\n", "password = abc123\n"},
		"double-quoted":         {`password = "${TRICKY}"`, `password = "a\\b\"c\'d$e{f}#;g"`},
		"single-quoted":         {`password = '${TRICKY}'`, `password = 'a\\b\"c\'d$e{f}#;g'`},
		"JSON":                  {`allowed_hosts = "${HOSTS}"`, `allowed_hosts = "[\"localhost\", \"127.0.0.1\"]"`},
		"quoted whitespace":     {`name = "${SPACE}"`, `name = "a b"`},
		"several":               {`base_url = "https://${PLAIN}/${SPACE}"`, `base_url = "https://abc123/a b"`},
		"CRLF":                  {"password = \"${TRICKY}\"\r\n", "password = \"a\\\\b\\\"c\\'d$e{f}#;g\"\r\n"},
		"comment":               {"; password = ${MISSING}\n", "; password = ${MISSING}\n"},
		"indented comment":      {"  ;password = ${MISSING}\n", "  ;password = ${MISSING}\n"},
		"not placeholders":      {"x = $PLAIN ${1PLAIN} ${PLAIN", "x = $PLAIN ${1PLAIN} ${PLAIN"},
		"other lines untouched": {"[general]\ninstalled = On\nkey = ${PLAIN}\n\n", "[general]\ninstalled = On\nkey = abc123\n\n"},
	}

	for name, tc := range tests {
		t.Run(name, func(t *testing.T) {
			var got, problems = render(tc.config, lookup)
			if len(problems) > 0 {
				t.Fatalf("unexpected problems: %q", problems)
			}
			if got != tc.want {
				t.Errorf("got %q, want %q", got, tc.want)
			}
		})
	}
}

func TestRenderProblems(t *testing.T) {
	var tests = map[string]struct {
		config string
		want   []string
	}{
		"unset":             {"x = ${MISSING}", []string{"line 1: MISSING is not set"}},
		"blank":             {`x = "${BLANK}"`, []string{"line 1: BLANK is not set"}},
		"LF":                {`x = "${LF}"`, []string{"line 1: LF contains a line break"}},
		"CR":                {`x = "${CR}"`, []string{"line 1: CR contains a line break"}},
		"unquoted space":    {"x = ${SPACE}", []string{"line 1: SPACE contains whitespace, so the value has to be in quotes"}},
		"unquoted tab":      {"x = ${TAB}", []string{"line 1: TAB contains whitespace, so the value has to be in quotes"}},
		"unquoted vertical": {"x = ${VTAB}", []string{"line 1: VTAB contains whitespace, so the value has to be in quotes"}},
		"half-quoted":       {`x = "${SPACE}`, []string{"line 1: SPACE contains whitespace, so the value has to be in quotes"}},
		"every problem shown": {"; ${MISSING}\na = ${PLAIN}\nb = ${MISSING} ${BLANK}\nc = ${SPACE}\n", []string{
			"line 3: MISSING is not set",
			"line 3: BLANK is not set",
			"line 4: SPACE contains whitespace, so the value has to be in quotes",
		}},
	}

	for name, tc := range tests {
		t.Run(name, func(t *testing.T) {
			var _, problems = render(tc.config, lookup)
			if !reflect.DeepEqual(problems, tc.want) {
				t.Errorf("got %q, want %q", problems, tc.want)
			}
		})
	}
}
