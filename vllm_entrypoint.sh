#!/bin/bash
# WSL2 workaround: patch vLLM is_uva_available() to always return True

python3 -c "
import re
path = '/usr/local/lib/python3.12/dist-packages/vllm/utils/platform_utils.py'
with open(path, 'r') as f:
    content = f.read()

# Replace is_uva_available to always return True (WSL2 handles pin_memory=False)
old = '''@cache
def is_uva_available() -> bool:
    \"\"\"Check if Unified Virtual Addressing (UVA) is available.\"\"\"
    # UVA requires pinned memory.
    from vllm.platforms import current_platform

    # TODO: Add more requirements for UVA if needed.
    return is_pin_memory_available() or current_platform.is_cpu()'''

new = '''@cache
def is_uva_available() -> bool:
    \"\"\"Check if Unified Virtual Addressing (UVA) is available.\"\"\"
    # WSL2 workaround: force UVA available (pin_memory handled by WSL)
    return True'''

if old in content:
    content = content.replace(old, new)
    with open(path, 'w') as f:
        f.write(content)
    print('Patched is_uva_available() to return True (WSL2 workaround)')
else:
    print('Pattern not found, checking content...')
    if 'is_uva_available' in content:
        print('is_uva_available found but pattern mismatch, using regex fallback')
        # Fallback: replace the return statement
        content = re.sub(
            r'def is_uva_available\(\) -> bool:.*?(?=\n@cache|\ndef |\Z)',
            'def is_uva_available() -> bool:\n    return True\n',
            content, flags=re.DOTALL
        )
        with open(path, 'w') as f:
            f.write(content)
        print('Patched via regex fallback')
    else:
        print('ERROR: is_uva_available not found!')
"

exec python3 -m vllm.entrypoints.openai.api_server "$@"
