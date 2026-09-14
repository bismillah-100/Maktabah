import yaml

with open('mkdocs.yml', 'r') as f:
    doc = yaml.load(f, Loader=yaml.UnsafeLoader)

def get_key(i):
    if isinstance(i, dict):
        return list(i.keys())[0].lower()
    return str(i).lower()

nav = doc.get('nav', [])
for item in nav:
    if "Feature Modules" in item:
        feature_modules = item["Feature Modules"]
        for feature in feature_modules:
            if "Library & Catalog" in feature:
                library = feature["Library & Catalog"]
                library.append({"Book Import (Offline)": "features/library/updates/bookimport.md"})
                library.sort(key=get_key)

class Dumper(yaml.Dumper):
    def increase_indent(self, flow=False, *args, **kwargs):
        return super().increase_indent(flow=flow, indentless=False)

with open('mkdocs.yml', 'w') as f:
    yaml.dump(doc, f, Dumper=Dumper, default_flow_style=False, sort_keys=False, allow_unicode=True)
