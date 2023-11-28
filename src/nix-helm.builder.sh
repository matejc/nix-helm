set -euo pipefail

mkdir -p $out/templates

if [[ ! -z "${valuesPath-}" ]]; then
    cat $valuesPath | gojsontoyaml > $out/values.yaml
fi

cat $chartPath | gojsontoyaml > $out/Chart.yaml

for file in $attrTemplates; do
    cat $(eval "echo \$${file}Path") | gojsontoyaml > $(eval "echo $out/templates/\$${file}Name")
done

for file in $fileTemplates; do
    cp $(eval "echo \$${file}") $(eval "echo \$out/templates/\$${file}Name")
done
