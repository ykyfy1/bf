#!/bin/bash
# ====================== HB合并脚本：按demo.txt频道优先级排序，保留#EXTINF+URL成对 ======================
# Secrets：M3U_URL1 M3U_URL2，填入完整 https://user:pass@xxx.pages.dev/zubo.m3u

# 配置参数
CITY_TOP_COUNT=30
MERGE_TOP_COUNT=100
MIN_SPEED_KB=30

# 清理旧文件
rm -rf txt repo1.m3u repo2.m3u zubo.txt zubo.m3u index.html functions dist tmp_all.txt tmp_ordered.txt
mkdir -p txt

echo "===== 下载远端两个m3u文件 ====="
curl -sL "${M3U_URL1}" -o repo1.m3u || { echo "❌仓库1 m3u下载失败"; exit 1; }
curl -sL "${M3U_URL2}" -o repo2.m3u || { echo "❌仓库2 m3u下载失败"; exit 2; }

echo "repo1.m3u size: $(du -h repo1.m3u)"
echo "repo2.m3u size: $(du -h repo2.m3u)"

# 1.合并两个m3u，不去重，只去掉多余#EXTM3U
> tmp_all.txt
sed '/^#EXTM3U/d' repo1.m3u >> tmp_all.txt
sed '/^#EXTM3U/d' repo2.m3u >> tmp_all.txt

# 2. 解析m3u，把 #EXTINF 和链接打包成一行，方便按频道名排序
awk '
/^#EXTINF/ {
    sub(/.*,/,"",$0);  #提取逗号后面频道名称
    name=$0;
    getline url;       #读取下一行播放地址
    print name"\t"prev_line"\t"url;
    prev_line=$0;
}
{prev_line=$0}
' tmp_all.txt > tmp_pack.txt

# 3. 使用demo.txt做优先级排序，demo内频道放前面，其余放后面
awk -F"\t" '
BEGIN{
    #读取demo.txt预设顺序
    if((getline<"demo.txt")>0){
        demo_idx=0;
        demo_name[$0]=++demo_idx;
        while((getline<"demo.txt")>0){
            demo_name[$0]=++demo_idx;
        }
        close("demo.txt");
    }
}
{
    chan_name=$1;
    extinfo=$2;
    url=$3;
    if(chan_name in demo_name){
        #在demo名单里，用demo序号作为排序key
        sortkey=demo_name[chan_name];
    }else{
        #不在demo名单，放到末尾
        sortkey=9999 + NR;
    }
    print sortkey"\t"extinfo"\n"url;
}
' tmp_pack.txt | sort -n | cut -f2- > tmp_ordered.txt

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
  return response;
}
EOF

# 打包静态文件到dist
mkdir -p dist
cp zubo.m3u index.html dist/
cp -r functions dist/

echo "✅ 合并完成！已按demo.txt频道名称顺序排序"
echo "==== 合并后总行数：$(wc -l zubo.txt)"
