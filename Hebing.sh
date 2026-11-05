#!/bin/bash
# ====================== HB合并脚本｜不限数量远端M3U｜同频道归集｜模糊匹配demo排序｜全部IP保留 ======================
# Github Secrets: M3U_URL_LIST  【一行一个链接，空行会自动跳过】
# demo.txt 放仓库根目录，一行一个频道名

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
  curl -sL "${url_trim}" -o "tmp_${RANDOM}.m3u" || { echo "❌下载失败: ${url_trim}"; exit 1; }
  # 删除#EXTM3U，追加到总文件
  sed '/^#EXTM3U/d' "tmp_${RANDOM}.m3u" >> tmp_all.txt
done <<< "${M3U_URL_LIST}"

# 预处理demo.txt：清洗名称，去除空格、横杠，转小写，记录排序序号
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

# 解析m3u，提取EXTINF行、URL，生成清洗后的频道key用于分组
awk '
/^#EXTINF/ {
    extinfo_full = $0
    sub(/.*,/,"",extinfo_full);
    chan_raw = extinfo_full
    gsub(/[ -]/,"",chan_raw);
    chan_key = tolower(chan_raw);
    getline url_line;
    print chan_key "\t" $0 "\t" url_line;
    next;
}
' tmp_all.txt > tmp_pack.txt

# 分组归集：同一个频道的所有条目放一起；按demo顺序优先
awk -F"\t" '
# 加载demo排序表
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
    # sort_id控制demo顺序，ckey实现同频道归集
    print sort_id "\t" ckey "\t" extinfo "\n" url
}
' tmp_pack.txt | sort -n -k1,1 -k2,2 | cut -f3- > tmp_ordered.txt

# 组装最终m3u
> zubo.txt
echo "#EXTM3U" > zubo.txt
cat tmp_ordered.txt >> zubo.txt
cp zubo.txt zubo.m3u

# 生成index.html兜底页面
echo "<pre>IPTV源：<a href='./zubo.m3u'>zubo.m3u</a></pre>" > index.html

# =========【扫描仓库同款鉴权 + 关闭CF缓存，解决密码时有时无】=========
mkdir -p functions
cat > functions/_middleware.js <<'EOF'
export async function onRequest({ request, env, next }) {
  const username = env.BASIC_AUTH_USERNAME;
  const password = env.BASIC_AUTH_PASSWORD;

  if (!username || !password) return next();

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

  const [, base64] = authHeader.split(" ");
  const [user, pass] = atob(base64).split(":");
  if (user !== username || pass !== password) {
    return new Response("账号密码错误", {
      status: 401,
      headers: { "Cache-Control": "no-store, no-cache, must-revalidate" }
    });
  }
  const response = await next();
  response.headers.set("Cache-Control", "no-store, no-cache, must-revalidate");
}
EOF

# 打包静态文件到dist
mkdir -p dist
cp zubo.m3u index.html dist/
cp -r functions dist/

echo "✅ 合并完成！不限数量远端M3U，同频道全部IP归集，模糊匹配"
echo "==== 合并后总行数：$(wc -l zubo.txt)"
