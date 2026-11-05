#!/bin/bash
# ====================== HB合并脚本【稳定输出版】修复行顺序错乱问题｜带容错鉴权middleware ======================
# Github Secrets: M3U_URL_LIST  一行一个远端m3u链接
# 根目录 demo.txt  一行一个频道名，用于自定义排序

# 配置参数
CITY_TOP_COUNT=30
MERGE_TOP_COUNT=100
MIN_SPEED_KB=30

# 清理旧临时文件
rm -rf txt repo*.m3u zubo.txt zubo.m3u index.html functions dist tmp_all.txt tmp_pack.txt tmp_ordered.txt demo_clean.txt
mkdir -p txt

> tmp_all.txt
echo "===== 读取远端链接列表并批量下载 ====="

# 循环读取M3U_URL_LIST内每一行链接
while IFS= read -r url; do
  # 去除首尾空白，空行直接跳过
  url_trim=$(echo "$url" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  if [[ -z "$url_trim" ]];then
    continue
  fi
  echo "🔽 正在下载: ${url_trim}"
  fname="tmp_${RANDOM}.m3u"
  curl -sL "${url_trim}" -o "${fname}" || { echo "❌下载失败: ${url_trim}"; exit 1; }
  # 删除#EXTM3U头部，其余内容追加到总文件
  sed '/^#EXTM3U/d' "${fname}" >> tmp_all.txt
  rm -f "${fname}"
done <<< "${M3U_URL_LIST}"

# 预处理demo.txt：清洗频道名称，生成排序映射
awk '{
    raw=$0
    gsub(/[ -]/,"",raw);
    key=tolower(raw);
    idx++;
    demo_sort[key]=idx;
    demo_name[idx]=$0;
}
END{
    for(i=1;i<=idx;i++) print demo_name[i] "\t" i
}' demo.txt > demo_clean.txt

# 解析m3u：读取EXTINF行 + 紧随其后URL，输出 频道key\tEXTINF\tURL
awk '
/^#EXTINF/ {
    extinfo = $0
    sub(/.*,/,"",extinfo);
    chan_raw = extinfo
    gsub(/[ -]/,"",chan_raw);
    chan_key = tolower(chan_raw);
    getline url;
    print chan_key "\t" $0 "\t" url;
    next;
}
' tmp_all.txt > tmp_pack.txt

# 加载demo排序，生成可排序完整记录：sort_id \t chan_key \t extinfo \t url
awk -F"\t" '
BEGIN{
    while((getline<"demo_clean.txt")>0){
        demo_key[$1]=$2
    }
    close("demo_clean.txt")
}
{
    ckey=$1;
    extinfo=$2;
    url=$3;
    if(ckey in demo_key){
        sort_id = demo_key[ckey]
    }else{
        sort_id = 9999
    }
    print sort_id "\t" ckey "\t" extinfo "\t" url
}
' tmp_pack.txt | sort -n -k1,1 -k2,2 > tmp_ordered.txt

# ========== 组装M3U【核心修复：保证#EXTINF永远在URL上方，不会乱行】==========
echo "#EXTM3U" > zubo.txt
while IFS=$'\t' read -r sortid ckey extinfo url; do
    echo "$extinfo" >> zubo.txt
    echo "$url" >> zubo.txt
done < tmp_ordered.txt

cp zubo.txt zubo.m3u

# 生成简单index.html页面
echo "<pre>IPTV播放列表：<a href='./zubo.m3u'>zubo.m3u</a></pre>" > index.html

# ========= 容错鉴权middleware，防止CF 1101崩溃 =========
mkdir -p functions
cat > functions/_middleware.js <<'EOF'
export async function onRequest({ request, env, next }) {
  const username = env.BASIC_AUTH_USERNAME;
  const password = env.BASIC_AUTH_PASSWORD;

  if (!username || !password) {
    return await next();
  }

  const authHeader = request.headers.get("authorization");
  if (!authHeader) {
    return new Response("需要输入访问密码", {
      status: 401,
      headers: {
        "WWW-Authenticate": 'Basic realm="IPTV"',
        "Cache-Control": "no-store, no-cache, must-revalidate"
      },
    });
  }

  try {
    const [scheme, base64] = authHeader.split(" ");
    if (scheme.toLowerCase() !== "basic" || !base64) throw new Error("auth error");
    const decoded = atob(base64);
    const [user, pass] = decoded.split(":");
    if (user !== username || pass !== password) {
      throw new Error("wrong password");
    }
  } catch (e) {
    return new Response("账号密码错误", {
      status: 401,
      headers: { "Cache-Control": "no-store, no-cache, must-revalidate" }
    });
  }

  const response = await next();
  response.headers.set("Cache-Control", "no-store, no-cache, must-revalidate");
  return response;
}
EOF

# 打包静态资源到dist目录
mkdir -p dist
cp zubo.m3u index.html dist/
cp -r functions dist/

echo "==== 输出文件清单 ===="
ls -la dist/
echo "✅ 合并脚本执行完成！m3u总行数：$(wc -l zubo.txt)"
