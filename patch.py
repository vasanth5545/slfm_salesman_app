import os
import re

import_stmt = "import 'package:slfm_salesman_app/services/activity_logger.dart';\n"

def process_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    parts = re.split(r'(ScaffoldMessenger\.of\([^)]+\)\.showSnackBar\()', content)
    
    if len(parts) == 1:
        return

    modified = False
    new_content = parts[0]
    
    for i in range(1, len(parts), 2):
        call_start = parts[i]
        rest = parts[i+1]
        
        snippet = rest[:500]
        if 'Colors.red' in snippet:
            last_newline = new_content.rfind('\n')
            indent = new_content[last_newline+1:] if last_newline != -1 else ''
            indent = ''.join(c for c in indent if c == ' ')
            
            logger_code = f"try {{ ActivityLogger.instance.log(category: 'Error', action: 'UI Error', details: {{'message': 'UI Error'}}); }} catch(_) {{}}\n{indent}"
            
            new_content += logger_code + call_start + rest
            modified = True
        else:
            new_content += call_start + rest

    if modified:
        if 'package:slfm_salesman_app/services/activity_logger.dart' not in new_content:
            first_import = new_content.find('import ')
            if first_import != -1:
                end_of_line = new_content.find('\n', first_import)
                new_content = new_content[:end_of_line+1] + import_stmt + new_content[end_of_line+1:]
            else:
                new_content = import_stmt + new_content
                
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(new_content)
        print(f'Patched {filepath}')

for root, dirs, files in os.walk('c:/Users/LENOVO/slfm_salesman_app/lib'):
    for file in files:
        if file.endswith('.dart'):
            process_file(os.path.join(root, file))
