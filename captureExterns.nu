, rg -U "pub extern .* fn .*\\(([^(]|\n)*\\) callconv\\(.*\\) .*;" --json
| split row "\n"
| each {|it| $it | from json }
| where { |it| $it.type == "match" }
| reduce { |it, acc|
    let code = $acc | get --optional ($it.data.path.text);

    $acc | merge { $it.data.path.text: ([$code, $it.data.lines.text, "\n"] | str join) }
  }
| explore
