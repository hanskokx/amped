# Converts Bamp's winamp_skin_specification.yaml (github.com/dp-mason/bamp,
# src/bamp) into assets/bamp/spec.json, the layer map the Dart converter reads.
#
#   ruby tool/bamp_spec_to_json.rb path/to/winamp_skin_specification.yaml
require "yaml"
require "json"

spec = YAML.load_file(ARGV.fetch(0), aliases: true)
layers = spec["bamp"].map do |file, maps|
  {
    "file" => file,
    "maps" => maps.map do |name, m|
      e = { "name" => name, "region" => m["region"], "dest" => m["dest"] }
      e["optionalHandle"] = true if m["optional_handle"]
      e
    end,
  }
end
classic = spec["classic"].transform_values do |f|
  out = { "resolution" => f["resolution"] }
  out["withoutHandle"] = f["resolution_without_handle"] if f["resolution_without_handle"]
  out["regions"] = f.select { |k, v| v.is_a?(Array) && v.length == 4 && k != "resolution" && k != "resolution_without_handle" }
  out
end
out = {
  "bampResolution" => spec["BAMP_RESOLUTION"],
  "extras" => spec["text_extras"].slice("COLOR_SAMPLE_SIZE", "PLEDIT_START", "VISCOLOR_TOTAL", "VISCOLOR_START", "PLEDIT_FIELDS", "PLEDIT_FONT"),
  "layers" => layers,
  "classic" => classic,
}
File.write(File.expand_path("../assets/bamp/spec.json", __dir__), JSON.generate(out))
