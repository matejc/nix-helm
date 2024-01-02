set -euo pipefail

mkdir -p $out/templates $out/bin
cp $__commandApplyPath $out/bin/apply.sh
cp $__commandDestroyPath  $out/bin/destroy.sh
cp $__commandPlanPath  $out/bin/plan.sh
cp $__commandStatusPath $out/bin/status.sh
chmod +x $out/bin/*

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
