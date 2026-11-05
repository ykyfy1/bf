#!/bin/bash
# ====================== HB合并脚本【多分组group-title，demo分段识别，频道模糊合并】 ======================
# Github Secrets: M3U_URL_LIST  一行一个远端m3u链接
# demo.txt格式示例：
# 公告,#genre#
# 更新日期
# 上海电信,#genre#
# CCTV1
# CCTV2
# CCTV3

# 配置参数
CITY_TOP_COUNT=30
MERGE_TOP_COUNT=100
MIN_SPEED_KB=30

# 清理旧临时文件
rm -rf txt repo*.m3u zubo.txt zubo.m3u index.html functions dist tmp_all.txt tmp_pack.txt tmp_ordered.txt demo_map.txt
mkdir -p txt

> tmp_all.txt
echo "===== 读取远端链接列表并批量下载 ====="

# =========【原版下载循环，完全不动】=========
while IFS= read -r url; do
  url_trim=$(echo "$url" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  if [[ -z "$url_trim" ]];then
    continue
  fi
  echo "🔽 正在下载: ${url_trim}"
  fname="tmp_${RANDOM}.m3u"
  curl -sL "${url_trim}" -o "${fname}" || { echo "❌下载失败: ${url_trim}"; exit 1; }
  sed '/^#EXTM3U/d' "${fname}" >> tmp_all.txt
  rm -f "${fname}"
done <<< "${M3U_URL_LIST}"
# ==============================================================

# 第一步：解析demo.txt，生成【分组名称 + 频道顺序映射】
# 输出格式： group名称 \t 清洗后的频道key \t 原始频道名 \t 排序编号
awk '
BEGIN{
    current_group="未知分组"
    sort_idx=0
}
{
    line=$0
    if (index(line,",#genre#")>0){
        sub(/,#genre#/,"",line)
        current_group = line
        next
    }
    # 普通频道行
    raw_chan = line
    gsub(/[ -]/,"",raw_chan);
    key=tolower(raw_chan);
    sort_idx++;
    print current_group "\t" key "\t" line "\t" sort_idx
}' demo.txt > demo_map.txt

# 第二步：解析所有下载回来的m3u，提取频道、链接
# 输出：清洗频道key \t 原始EXTINF \t URL
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

# 第三步：关联demo分组+排序
# 读取demo映射表，匹配频道，拿到所属分组和sortid
awk -F"\t" '
BEGIN{
    while((getline<"demo_map.txt")>0){
        g=$1; k=$2; name=$3; sid=$4
        group_key[k]=g
        sort_key[k]=sid
    }
    close("demo_map.txt")
}
{
    ckey=$1; ext_raw=$2; url=$3;
    if(ckey in group_key){
        gname=group_key[ckey]
        sid=sort_key[ckey]
    }else{
        gname="其他"
        sid=9999
    }
    print sid "\t" gname "\t" ckey "\t" ext_raw "\t" url
}
' tmp_pack.txt | sort -n -k1,1 -k2,2 > tmp_ordered.txt

# 第四步：组装最终m3u，自动写入 group-title=""
echo "#EXTM3U" > zubo.txt
last_group=""
while IFS=$'\t' read -r sortid gname ckey ext_raw url; do
    # 提取原始频道名称（逗号后面）
    chan_name="${ext_raw#*,}"
    # 重写EXTINF，插入group-title
    new_ext="#EXTINF:-1 group-title=\"${gname}\",${chan_name}"
    echo "${new_ext}" >> zubo.txt
    echo "${url}" >> zubo.txt
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
