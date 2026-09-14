import yaml

with open('mkdocs.yml', 'r') as f:
    doc = yaml.load(f, Loader=yaml.UnsafeLoader)

def get_key(i):
    if isinstance(i, dict):
        return list(i.keys())[0].lower()
    return str(i).lower()

nav = doc.get('nav', [])
for item in nav:
    if "Core Architecture" in item:
        core_arch = item["Core Architecture"]
        core_arch.append({"App Configuration": "core/configuration.md"})
        core_arch.sort(key=get_key)

class Dumper(yaml.Dumper):
    def increase_indent(self, flow=False, *args, **kwargs):
        return super().increase_indent(flow=flow, indentless=False)

with open('mkdocs.yml', 'w') as f:
    yaml.dump(doc, f, Dumper=Dumper, default_flow_style=False, sort_keys=False, allow_unicode=True)
