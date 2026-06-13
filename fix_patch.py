import os
import re

def fix_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    # Pattern: try { ActivityLogger.instance.log(category: 'Error', action: 'UI Error', details: {'message': 'UI Error'}); } catch(_) {}
    old_pattern = "try { ActivityLogger.instance.log(category: 'Error', action: 'UI Error', details: {'message': 'UI Error'}); } catch(_) {}"
    new_pattern = "try { ActivityLogger.instance.logError('UI', 'Snackbar error shown'); } catch(_) {}"

    if old_pattern in content:
        content = content.replace(old_pattern, new_pattern)
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f'Fixed: {filepath}')

for root, dirs, files in os.walk(r'c:\Users\LENOVO\slfm_salesman_app\lib'):
    for file in files:
        if file.endswith('.dart'):
            fix_file(os.path.join(root, file))

print("Done!")
