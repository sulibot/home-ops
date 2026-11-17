package main

import (
	"bytes"
	"fmt"
	"os"
	"strings"
	"text/template"
	"unicode/utf8"
)

func main() {
	b, e := os.ReadFile(os.Args[1])
	if e != nil {
		panic(e)
	}
	t := template.Must(template.New("pushover").Parse(string(b)))
	for _, n := range []int{0, 1, 3, 1000} {
		alerts := []map[string]any{}
		for i := 0; i < n; i++ {
			alerts = append(alerts, map[string]any{"Labels": map[string]string{"namespace": strings.Repeat("界", 200), "job_name": strings.Repeat("界", 200)}, "Annotations": map[string]string{"summary": strings.Repeat("界", 500)}})
		}
		var out bytes.Buffer
		if e = t.Execute(&out, map[string]any{"Alerts": alerts}); e != nil {
			panic(e)
		}
		count := utf8.RuneCount(out.Bytes())
		if count > 1024 {
			panic(fmt.Sprintf("%d alerts: %d runes", n, count))
		}
		fmt.Printf("%d alerts: %d/1024 characters\n", n, count)
	}
}
