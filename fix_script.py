# Run this from inside your axion folder:
# python fix_script.py

with open('.apply_full_redesign.ps1', 'rb') as f:
    content = f.read()

lines = content.split(b'\n')
fixed = []
count = 0
for line in lines:
    stripped = line.rstrip(b'\r')
    if stripped == b"'":
        fixed.append(b"'@\r")
        count += 1
    else:
        fixed.append(line)

result = b'\n'.join(fixed)
with open('.apply_full_redesign.ps1', 'wb') as f:
    f.write(result)

print(f"Fixed {count} broken terminators. Now run: . '.apply_full_redesign.ps1'")