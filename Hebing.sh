#!/bin/bash
# ====================== HB合并脚本【原版下载逻辑保留｜仅修改排序】 ======================
# Github Secrets: M3U_URL_LIST  一行一个远端m3u链接
# 根目录 demo.txt  一行一个频道名，用于自定义排序

# 配置参数
CITY_TOP_COUNT=30
MERGE_TOP_COUNT=100
MIN_SPEED_KB=30

# 清理旧临时文件
rm -rf txt repo*.m3u zubo.txt zubo.m3u index.html functions dist tmp_all.txt tmp_pack.txt demo_clean.txt
mkdir -p txt

> tmp_all.txt
echo "===== 读取远端链接列表并批量下载 ====="

# =====================【原版下载代码原样保留！！多链接正常读取】=====================
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
# ==================================================================================

# ===================== 【新增：只改这部分，实现按demo排序，同频道全部放一起】 =====================
# 1.读取demo.txt，保存顺序
declare -A chanOrder
demoList=()
orderIdx=0
while IFS= read -r line; do
    lineTrim=$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    [[ -z "$lineTrim" ]] && continue
    chanOrder["$lineTrim"]=$orderIdx
    demoList+=("$lineTrim")
    orderIdx=$((orderIdx+1))
done < demo.txt

# 2.解析tmp_all.txt，按频道归类所有 #EXTINF + URL
declare -A chanData
currentExt=""
while IFS= read -r line; do
    if [[ "$line" == "#EXTINF:"* ]];then
        currentExt="$line"
        #提取逗号后面频道名称
        chanName=$(echo "$currentExt" | sed -E 's/.*,(.+)$/\1/')
        continue
    fi
    if [[ -n "$currentExt" && "$line" != "#"* && -n "$line" ]];then
        chanData["$chanName"]+="${currentExt}"$'\n'"${line}"$'\n'
        currentExt=""
    fi
done < tmp_all.txt

# 3.按照demo.txt顺序输出
echo "#EXTM3U" > zubo.txt
for name in "${demoList[@]}"; do
    if [[ -n "${chanData[$name]}" ]];then
        echo -n "${chanData[$name]}" >> zubo.txt
    fi
done
# ==================================================================================

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
echo "📝 tmp_all原始合并总行数：$(wc -l tmp_all.txt)"
echo "✅ 合并脚本执行完成！m3u总行数：$(wc -l zubo.txt)"
