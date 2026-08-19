import requests, sys, re, importlib.util
p='F:/Downloads/a.py'
spec=importlib.util.spec_from_file_location('a',p); a=importlib.util.module_from_spec(spec); spec.loader.exec_module(a)
s,c=a.load_youtube_cookies(); html=s.get(a.YOUTUBE_ORIGIN+'/playlist?list='+a.DEFAULT_PLAYLIST_ID,timeout=45).text
idx=html.find('ytcfg.set('); print('idx',idx); print(html[idx:idx+1000])
