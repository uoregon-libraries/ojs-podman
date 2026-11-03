// render-config prints an OJS config file with each "${VAR}" placeholder
// replaced by the value of environment variable VAR. Placeholders in comments
// are left alone.
//
// Nothing is printed, and the exit status is 1, if any placeholder can't be
// filled in safely: its var is unset or blank, has a line break, or has
// whitespace in an unquoted value (OJS would cut the value off there).
//
// OJS strips backslashes from quoted values, so those get escaped, e.g.,
// `password = "${MYSQL_PASSWORD}"` works for any password.
//
// The rules for comments and quoted values copy OJS's ConfigParser::readConfig
// (lib/pkp/classes/config/ConfigParser.php), so check that when upgrading OJS.
package main

import (
	"fmt"
	"os"
	"regexp"
	"strings"
)

var placeholder = regexp.MustCompile(`\$\{[A-Za-z_][A-Za-z0-9_]*\}`)

// Same check OJS uses to decide a value is a quoted string
var quotedValue = regexp.MustCompile(`^["'].*["']$`)

// OJS uses PHP's trim() and PCRE's \s, which don't match Go's idea of
// whitespace
const phpTrimChars = " \t\n\r\x00\x0b"
const pcreSpaceChars = " \t\n\v\f\r"

// Same as PHP's addslashes, which undoes OJS's stripslashes (minus NUL, which
// can't be in an env var)
var addSlashes = strings.NewReplacer(`\`, `\\`, `"`, `\"`, `'`, `\'`)

// render returns config with its placeholders filled in from lookup, or a list
// of problems if any couldn't be
func render(config string, lookup func(string) (string, bool)) (string, []string) {
	var out strings.Builder
	var problems []string
	for i, line := range strings.SplitAfter(config, "\n") {
		if strings.HasPrefix(strings.TrimLeft(line, phpTrimChars), ";") || !strings.Contains(line, "${") {
			out.WriteString(line)
			continue
		}

		var _, value, _ = strings.Cut(line, "=")
		var quoted = quotedValue.MatchString(strings.Trim(value, phpTrimChars))

		out.WriteString(placeholder.ReplaceAllStringFunc(line, func(match string) string {
			var name = match[2 : len(match)-1]
			var val, _ = lookup(name)
			var where = fmt.Sprintf("line %d", i+1)
			switch {
			case val == "":
				problems = append(problems, fmt.Sprintf("%s: %s is not set", where, name))
			case strings.ContainsAny(val, "\r\n"):
				problems = append(problems, fmt.Sprintf("%s: %s contains a line break", where, name))
			case quoted:
				return addSlashes.Replace(val)
			case strings.ContainsAny(val, pcreSpaceChars):
				problems = append(problems, fmt.Sprintf("%s: %s contains whitespace, so the value has to be in quotes", where, name))
			default:
				return val
			}
			return match
		}))
	}

	return out.String(), problems
}

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "Usage: render-config <config file>")
		os.Exit(2)
	}

	var fname = os.Args[1]
	var data, err = os.ReadFile(fname)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	var out, problems = render(string(data), os.LookupEnv)
	if len(problems) > 0 {
		fmt.Fprintf(os.Stderr, "Can't fill in placeholders in %s:\n  %s\n", fname, strings.Join(problems, "\n  "))
		os.Exit(1)
	}

	_, err = os.Stdout.WriteString(out)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
