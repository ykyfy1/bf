import os
# 从Github Secrets的M3U_URL_LIST读取远端m3u链接
source_urls = [line.strip() for line in os.getenv("M3U_URL_LIST","").splitlines() if line.strip()]

# EPG地址，自行修改
epg_urls = [
    "https://epg.51zmt.top:8000/api/epg.xml"
]

# IP版本优先级 ipv6 / ipv4
ip_version_priority = "ipv6"

# URL黑名单，包含下面字符直接过滤
url_blacklist = []

# 公告栏
announcements = [
    {
        "channel": "公告",
        "entries": [
            {
                "name": None,
                "logo": "",
                "url": ""
            }
        ]
    }
]
