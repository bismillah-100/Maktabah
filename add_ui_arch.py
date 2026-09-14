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
        
        # Check if they exist to avoid duplicates
        has_macos = any("UI Core (macOS)" in k for k in core_arch if isinstance(k, dict))
        has_ios = any("UI Core (iOS)" in k for k in core_arch if isinstance(k, dict))
        
        if not has_macos:
            core_arch.append({"UI Core (macOS)": [{"SplitVC & Window": "core/macos/splitvc.md"}]})
        if not has_ios:
            core_arch.append({"UI Core (iOS)": [{"iOSMainView & Layout": "core/ios/mainview.md"}]})
            
        core_arch.sort(key=get_key)

class Dumper(yaml.Dumper):
    def increase_indent(self, flow=False, *args, **kwargs):
        return super().increase_indent(flow=flow, indentless=False)

with open('mkdocs.yml', 'w') as f:
    yaml.dump(doc, f, Dumper=Dumper, default_flow_style=False, sort_keys=False, allow_unicode=True)
