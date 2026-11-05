#!/bin/bash
# ====================== HB合并脚本【保留原始EXTINF，追加group-title；同频道聚合】 ======================
# Github Secrets: M3U_URL_LIST 一行一个远端m3u链接
# demo.txt示例
# 公告,#genre#
# 更新日期
# 上海电信,#genre#
# CCTV1
# CCTV2

# 配置参数
CITY_TOP_COUNT=30
MERGE_TOP_COUNT=100
MIN_SPEED_KB=30

# 清理临时文件
rm -rf txt repo*.m3u zubo.txt zubo.m3u index.html functions dist tmp_all.txt tmp_pack.txt tmp_ordered.txt demo_map.txt
mkdir -p txt

> tmp_all.txt
echo "===== 读取远端链接列表并批量下载 ====="

# 下载远端m3u，合并全部内容
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

# 1.解析demo.txt，生成：分组名 \t 清洗频道key \t 原始频道名 \t 排序编号
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
    raw_chan = line
    gsub(/[ -]/,"",raw_chan);
    key=tolower(raw_chan);
    sort_idx++;
    print current_group "\t" key "\t" line "\t" sort_idx
}' demo.txt > demo_map.txt

# 2.解析下载后的m3u，提取：清洗频道key | 原始完整EXTINF行 | url
awk '
/^#EXTINF/ {
    ext_full = $0
    # 提取逗号后的频道名称
    sub(/.*,/,"",ext_full);
    chan_raw = ext_full
    gsub(/[ -]/,"",chan_raw);
    chan_key = tolower(chan_raw);
    getline url;
    print chan_key "\t" $0 "\t" url;
    next;
}
' tmp_all.txt > tmp_pack.txt

# 3.关联demo的分组和排序号
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
' tmp_pack.txt | sort -n -k1,1 > tmp_ordered.txt

# 4.组装m3u：**在原始#EXTINF里面追加 group-title="xxx"，不覆盖原有内容**
echo "#EXTM3U" > zubo.txt
while IFS=$'\t' read -r sortid gname ckey ext_raw url; do
    # ext_raw 是原始完整#EXTINF行
    # 在逗号前插入 group-title="分组"
    if [[ "$ext_raw" == *,* ]]; then
        # 拆分：逗号前面部分 + 逗号后面频道名
        prefix="${ext_raw%,*}"
        chan_name="${ext_raw#*,}"
        new_ext="${prefix} group-title=\"${gname}\",${chan_name}"
    else
        new_ext="${ext_raw} group-title=\"${gname}\""
    fi
    echo "${new_ext}" >> zubo.txt
    echo "${url}" >> zubo.txt
done < tmp_ordered.txt

cp zubo.txt zubo.m3u

# 页面
echo "<pre>IPTV播放列表：<a href='./zubo.m3u'>zubo.m3u</a></pre>" > index.html

# CF鉴权中间件
mkdir -p functions
cat > functions/_middleware.js <<'EOF'
export async function onRequest({ request, env, next }) {
  const username = env.BASIC_AUTH_USERNAME;
  const password = env.BASIC_AUTH_PASSWORD;
  if (!username || !password) return await next();
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
    if (scheme.toLowerCase() !== "basic" || !base64) throw new Error();
    const decoded = atob(base64);
    const [user, pass] = decoded.split(":");
    if (user !== username || pass !== password) throw new Error();
  } catch (e) {
    return new Response("账号密码错误", {
      status: 401,
      headers: { "Cache-Control": "no-store, no-cache, must-revalidate" }
    });
  }
  const res = await next();
  res.headers.set("Cache-Control", "no-store, no-cache, must-revalidate");
  return res;
}
EOF

mkdir -p dist
cp zubo.m3u index.html dist/
cp -r functions dist/

echo "==== 输出文件清单 ===="
ls -la dist/
echo "✅ 执行完成，m3u总行数：$(wc -l zubo.txt)"
