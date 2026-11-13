#!/usr/bin/env python3
"""Accélère le démarrage de la version web de Katika (à lancer après flutter build web).

 1. écran de démarrage Katika affiché tout de suite (au lieu d'une page blanche)
 2. couleurs du manifeste PWA alignées sur l'appli
 3. service worker qui garde l'appli, le moteur et les polices en mémoire
 4. préchargement du code principal en parallèle
Usage : python3 tools/web_boost.py build/web
"""
import json, os, re, sys, time

root = sys.argv[1] if len(sys.argv) > 1 else 'build/web'
build_id = os.environ.get('GITHUB_SHA', '')[:10] or str(int(time.time()))
here = os.path.dirname(os.path.abspath(__file__))

# --- 1 + 4 : index.html ---------------------------------------------------
p = os.path.join(root, 'index.html')
html = open(p, encoding='utf-8').read()
if 'kt-splash' not in html:
    head = (
        '<meta name="theme-color" content="#061A66">\n'
        '<link rel="preload" href="main.dart.js" as="script">\n'
        '<style>html,body{margin:0;height:100%;background:#061A66}'
        '#kt-splash{position:fixed;inset:0;z-index:99999;display:flex;flex-direction:column;'
        'align-items:center;justify-content:center;background:#061A66;transition:opacity .35s ease}'
        '#kt-splash img{width:120px;height:120px;border-radius:26px;box-shadow:0 8px 28px rgba(0,0,0,.45)}'
        '#kt-splash b{margin-top:18px;font:800 30px/1 system-ui,sans-serif;color:#fff;letter-spacing:.5px}'
        '#kt-splash b i{font-style:normal;color:#FFC21A}'
        '#kt-splash u{margin-top:26px;width:34px;height:34px;border:4px solid rgba(255,255,255,.25);'
        'border-top-color:#FFC21A;border-radius:50%;animation:kts .8s linear infinite}'
        '@keyframes kts{to{transform:rotate(360deg)}}</style>\n'
    )
    body = (
        '<div id="kt-splash"><img src="/icon-192.png" alt="" onerror="this.style.display=\'none\'">'
        '<b>Kati<i>ka</i></b><u></u></div>\n'
        '<script>window.addEventListener("flutter-first-frame",function(){'
        'var s=document.getElementById("kt-splash");if(!s)return;s.style.opacity="0";'
        'setTimeout(function(){s.remove()},400)});</script>\n'
    )
    html = html.replace('</head>', head + '</head>', 1)
    html = re.sub(r'(<body[^>]*>)', r'\1\n' + body.replace('\\', '\\\\'), html, count=1)
    open(p, 'w', encoding='utf-8').write(html)

# --- 2 : manifeste -----------------------------------------------------------
mp = os.path.join(root, 'manifest.json')
if os.path.exists(mp):
    m = json.load(open(mp, encoding='utf-8'))
    m['background_color'] = '#061A66'
    m['theme_color'] = '#061A66'
    json.dump(m, open(mp, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)

# --- 3 : service worker ---------------------------------------------------------
engine = 'x'
bp = os.path.join(root, 'flutter_bootstrap.js')
if os.path.exists(bp):
    mm = re.search(r'engineRevision"\s*:\s*"([a-f0-9]+)"', open(bp, encoding='utf-8').read())
    if mm:
        engine = mm.group(1)[:12]
sw = open(os.path.join(here, 'sw_template.js'), encoding='utf-8').read()
sw = sw.replace('__BUILD__', build_id).replace('__ENGINE__', engine)
open(os.path.join(root, 'flutter_service_worker.js'), 'w', encoding='utf-8').write(sw)
print('web_boost : OK (build %s, moteur %s)' % (build_id, engine))
