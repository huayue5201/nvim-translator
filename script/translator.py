# -*- coding: utf-8 -*-
import json
import threading
import time
import random
import copy
import sys
import re
import os
from urllib.parse import quote_plus as url_quote, urlencode, urlparse
from urllib.request import Request, urlopen
from urllib.error import URLError, HTTPError

is_py3 = sys.version_info.major >= 3


# ---------------- Base Translator ---------------- #
class BaseTranslator:
    def __init__(self, name):
        self._name = name
        self._proxy_url = None

    def request(self, url, data=None, post=False, headers=None):
        if headers is None:
            headers = {"User-Agent": "Mozilla/5.0"}
        data_bytes = None
        if post and data:
            data_bytes = urlencode(data).encode("utf-8")
        elif data:
            url += "?" + "&".join(f"{k}={url_quote(str(v))}" for k, v in data.items())

        req = Request(url, data_bytes, headers)
        try:
            resp = urlopen(req, timeout=5)
            charset = resp.headers.get_content_charset("utf-8")
            return resp.read().decode(charset)
        except (URLError, HTTPError, TimeoutError) as e:
            sys.stderr.write(f"{self._name} request error: {e}\n")
            return None

    def set_proxy(self, proxy_url=None):
        try:
            import socks
            import socket
        except ImportError:
            sys.stderr.write("pySocks module should be installed\n")
            return
        if not proxy_url:
            return
        self._proxy_url = proxy_url
        url_comp = urlparse(proxy_url)
        proxy_type = {
            "http": socks.PROXY_TYPE_HTTP,
            "socks": socks.PROXY_TYPE_SOCKS5,
            "socks4": socks.PROXY_TYPE_SOCKS4,
            "socks5": socks.PROXY_TYPE_SOCKS5,
        }
        socks.set_default_proxy(
            proxy_type.get(url_comp.scheme, socks.PROXY_TYPE_HTTP),
            url_comp.hostname,
            url_comp.port,
            True,
            url_comp.username,
            url_comp.password,
        )
        socket.socket = socks.socksocket

    def translate(self, sl, tl, text, options=None):
        return {
            "engine": self._name,
            "sl": sl,
            "tl": tl,
            "text": text,
            "phonetic": "",
            "paraphrase": "",
            "explains": [],
            "alternative": [],
        }


# ---------------- Google ---------------- #
class GoogleTranslator(BaseTranslator):
    def __init__(self):
        super().__init__("google")
        self._host = "translate.googleapis.com"

    def get_url(self, sl, tl, text):
        return (
            f"https://{self._host}/translate_a/single?client=gtx&sl={sl}&tl={tl}"
            f"&dt=t&dt=bd&dt=ex&q={url_quote(text)}"
        )

    def translate(self, sl, tl, text, options=None):
        url = self.get_url(sl, tl, text)
        resp_text = self.request(url)
        res = super().translate(sl, tl, text)
        if not resp_text:
            return res
        try:
            obj = json.loads(resp_text)
        except Exception:
            return res

        try:
            res["paraphrase"] = "".join([p[0] for p in obj[0] if p[0]])
        except:
            pass

        explains = []
        try:
            if len(obj) > 1 and obj[1]:
                for x in obj[1]:
                    if not x or len(x) < 3 or x[2] is None:
                        continue
                    expl = f"[{x[0][0]}] " + ";".join(i[0] for i in x[2] if i)
                    explains.append(expl)
        except:
            pass
        res["explains"] = explains

        alts = []
        try:
            if len(obj) > 5 and obj[5]:
                base = res["paraphrase"]
                for x in obj[5]:
                    if not x or len(x) < 3 or x[2] is None:
                        continue
                    for i in x[2]:
                        if i and i[0] != base:
                            alts.append(f"* {i[0]}")
        except:
            pass
        res["alternative"] = alts

        try:
            for x in obj[0]:
                if len(x) >= 4 and x[3]:
                    res["phonetic"] = x[3]
                    break
        except:
            pass
        return res


# ---------------- Youdao ---------------- #
class YoudaoTranslator(BaseTranslator):
    def __init__(self):
        super().__init__("youdao")

    def translate(self, sl, tl, text, options=None):
        from hashlib import md5

        salt = str(int(time.time() * 1000) + random.randint(0, 10))
        s = "fanyideskweb" + text + salt + "97_3(jkMYg@T[KZQmqjTK"
        sign = md5(s.encode("utf-8")).hexdigest()
        data = {
            "i": text,
            "from": sl,
            "to": tl,
            "smartresult": "dict",
            "client": "fanyideskweb",
            "salt": salt,
            "sign": sign,
            "doctype": "json",
            "version": "2.1",
            "action": "FY_BY_CL1CKBUTTON",
        }
        headers = {
            "User-Agent": "Mozilla/5.0",
            "Referer": "http://fanyi.youdao.com/",
            "Cookie": "OUTFOX_SEARCH_USER_ID=-2022895048@10.168.8.76;",
        }
        resp_text = self.request(
            "https://fanyi.youdao.com/translate_o", data, post=True, headers=headers
        )
        res = super().translate(sl, tl, text)
        if not resp_text:
            return res
        try:
            obj = json.loads(resp_text)
        except:
            return res
        try:
            t = obj.get("translateResult")
            res["paraphrase"] = ", ".join([m.get("tgt", "") for n in t for m in n])
        except:
            pass
        try:
            entries = obj.get("smartResult", {}).get("entries", [])
            res["explains"] = [
                e.replace("\r", "").replace("\n", "") for e in entries if e.strip()
            ]
        except:
            pass
        return res


# ---------------- Baidu ---------------- #
class BaiduTranslator(BaseTranslator):
    def __init__(self):
        super().__init__("baidu")

    def translate(self, sl, tl, text, options=None):
        url = f"https://fanyi.baidu.com/sug"
        data = {"kw": text}
        resp_text = self.request(url, data, post=True)
        res = super().translate(sl, tl, text)
        if not resp_text:
            return res
        try:
            obj = json.loads(resp_text)
            items = obj.get("data", [])
            res["explains"] = [i.get("v", "") for i in items if i.get("v")]
        except:
            pass
        return res


# ---------------- Bing ---------------- #
class BingTranslator(BaseTranslator):
    def __init__(self):
        super().__init__("bing")

    def translate(self, sl, tl, text, options=None):
        url = f"https://www.bing.com/ttranslatev3?from={sl}&to={tl}&text={url_quote(text)}"
        resp = self.request(url)
        res = super().translate(sl, tl, text)
        if not resp:
            return res
        try:
            obj = json.loads(resp)
            if obj and isinstance(obj, list):
                data = obj[0]
                res["paraphrase"] = data.get("translations", [{}])[0].get("text", "")
        except:
            pass
        return res


# ---------------- Baicizhan ---------------- #
class BaicizhanTranslator(BaseTranslator):
    def __init__(self):
        super().__init__("baicizhan")

    def translate(self, sl, tl, text, options=None):
        url = "http://mall.baicizhan.com/ws/search"
        data = {"w": url_quote(text)}
        resp = self.request(url, data)
        res = super().translate(sl, tl, text)
        if not resp:
            return res
        try:
            obj = json.loads(resp)
            mean_cn = obj.get("mean_cn", "")
            res["explains"] = [mean_cn] if mean_cn else []
        except:
            pass
        return res


# ---------------- Haici ---------------- #
class HaiciTranslator(BaseTranslator):
    def __init__(self):
        super().__init__("haici")

    def translate(self, sl, tl, text, options=None):
        url = f"http://dict.cn/mini.php?q={url_quote(text)}"
        resp = self.request(url)
        res = super().translate(sl, tl, text)
        if not resp:
            return res
        try:
            items = re.findall(r'<div id="e">(.*?)</div>', resp)
            explains = []
            for item in items:
                parts = item.split("<br>")
                for p in parts:
                    if p.strip():
                        explains.append(p.strip())
            res["explains"] = explains
        except:
            pass
        return res


# ---------------- ICiba ---------------- #
class ICibaTranslator(BaseTranslator):
    def __init__(self):
        super().__init__("iciba")

    def translate(self, sl, tl, text, options=None):
        url = f"http://www.iciba.com/index.php?a=getWordMean&c=search&word={url_quote(text)}"
        resp = self.request(url)
        res = super().translate(sl, tl, text)
        if not resp:
            return res
        try:
            obj = json.loads(resp)
            sym = obj.get("baesInfo", {}).get("symbols", [{}])[0]
            explains = []
            parts = sym.get("parts", [])
            for p in parts:
                for m in p.get("means", []):
                    explains.append(f"{p.get('part', '')}: {m}")
            res["explains"] = explains
            res["phonetic"] = sym.get("ph_en", "")
        except:
            pass
        return res


# ---------------- Translate Shell ---------------- #
class TranslateShell(BaseTranslator):
    def __init__(self):
        super().__init__("trans")

    def translate(self, sl, tl, text, options=None):
        res = super().translate(sl, tl, text)
        try:
            cmd = f"trans -no-ansi -no-theme -show-languages n -show-prompt-message n -show-translation-phonetics n -hl {tl} '{text}'"
            run = os.popen(cmd)
            lines = [line.strip() for line in run.readlines() if line.strip()]
            run.close()
            res["explains"] = lines
        except:
            pass
        return res


# ---------------- Sdcv ---------------- #
class SdcvTranslator(BaseTranslator):
    def __init__(self):
        super().__init__("sdcv")

    def translate(self, sl, tl, text, options=None):
        res = super().translate(sl, tl, text)
        try:
            cmd = f"sdcv -u '朗道英汉字典5.0' '{text}'"
            run = os.popen(cmd)
            lines = [
                line.strip()
                for line in run.readlines()
                if line.strip()
                and not line.startswith("-->")
                and not line.startswith("*")
            ]
            run.close()
            res["explains"] = lines
        except:
            pass
        return res


# ---------------- Engines Map ---------------- #
ENGINES = {
    "google": GoogleTranslator,
    "youdao": YoudaoTranslator,
    "baidu": BaiduTranslator,
    "bing": BingTranslator,
    "baicizhan": BaicizhanTranslator,
    "haici": HaiciTranslator,
    "iciba": ICibaTranslator,
    "trans": TranslateShell,
    "sdcv": SdcvTranslator,
}


# ---------------- Main Runner ---------------- #
def main():
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("--engines", nargs="+", default=["google"])
    parser.add_argument("--target_lang", default="zh")
    parser.add_argument("--source_lang", default="en")
    parser.add_argument("--proxy", default=None)
    parser.add_argument("text", nargs="+", type=str)
    args = parser.parse_args()

    text = " ".join(args.text).strip()
    translation = {"text": text, "status": 1, "results": []}

    def runner(translator):
        res = translator.translate(args.source_lang, args.target_lang, text)
        if res:
            translation["results"].append(copy.deepcopy(res))
        else:
            translation["status"] = 0

    threads = []
    for e in args.engines:
        cls = ENGINES.get(e)
        if not cls:
            continue
        t_obj = cls()
        if args.proxy:
            t_obj.set_proxy(args.proxy)
        t = threading.Thread(target=runner, args=(t_obj,))
        threads.append(t)

    for t in threads:
        t.start()
    for t in threads:
        t.join()

    sys.stdout.write(json.dumps(translation, ensure_ascii=False))


if __name__ == "__main__":
    main()
