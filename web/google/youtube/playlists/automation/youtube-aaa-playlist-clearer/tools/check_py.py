import sys
print(sys.version)
for m in ['requests','cryptography','sqlite3']:
    try:
        __import__(m); print(m,'OK')
    except Exception as e: print(m,'MISSING',e)
