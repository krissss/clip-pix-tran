# 发版说明

ClipPixTran 的 GitHub Release 使用固定 Apple Development 签名生成 ZIP/DMG。这样同一
bundle identifier 和同一 TeamIdentifier 下，macOS TCC 对辅助功能、屏幕录制等权限的识别
会更稳定，用户更新后更不容易重新授权。

## GitHub Secrets

在仓库的 `Prod` environment 中配置：

| Secret | 说明 |
| --- | --- |
| `SIGNING_CERTIFICATE_P12` | Apple Development 证书和私钥导出的 `.p12`，base64 编码后填入 |
| `SIGNING_CERTIFICATE_PASSWORD` | 导出 `.p12` 时设置的密码 |
| `SIGNING_IDENTITY` | 证书身份，例如 `Apple Development: name@example.com (TEAM_ID)` |
| `DEVELOPMENT_TEAM` | Apple Developer Team ID，例如 `YOUR_TEAM_ID` |
| `SPARKLE_PRIVATE_KEY` | Sparkle EdDSA 私钥，用于签名更新包 |
| `HOMEBREW_TAP_TOKEN` | 可选，用于更新 Homebrew tap |

`SIGNING_CERTIFICATE_P12` 必须包含证书和对应私钥。推荐在 Keychain Access 中选中
`Apple Development: ...` identity（左侧分类选择 My Certificates / 我的证书），导出为
`.p12` 后再 base64 编码：

```bash
base64 -i signing-certificate.p12 | tr -d '\n' | pbcopy
```

如果 workflow 报 `.p12` 不包含证书或私钥，通常是只导出了证书本身、只导出了私钥，或
没有从 My Certificates 中带展开私钥的 identity 导出。

## 触发发版

推送 tag 会构建并发布正式 Release：

```bash
git tag v0.2.1
git push origin v0.2.1
```

也可以在 Actions 页面手动触发 `Release` workflow，并填写要打包的 tag。

CI 会执行：

1. 运行测试 workflow。
2. 导入 `SIGNING_CERTIFICATE_P12`。
3. 写入 `Config/Signing.local.xcconfig`。
4. 运行 `make package-signed` 生成同名 release 资产。
5. 校验签名中存在 `Apple Development` authority，并且 `TeamIdentifier` 等于 `DEVELOPMENT_TEAM`。
6. 签名 Sparkle 更新包，更新 `docs/appcast.xml`，上传 ZIP/DMG。

## 本机验证

本机可以先跑一遍同样的签名包流程：

```bash
make package-signed \
  TAG=v0.2.1 \
  SIGNED_CODE_SIGN_IDENTITY="Apple Development" \
  SIGNED_DEVELOPMENT_TEAM=YOUR_TEAM_ID
```

如果只想本机运行签名版来验证 TCC：

```bash
make run-signed \
  SIGNED_CODE_SIGN_IDENTITY="Apple Development" \
  SIGNED_DEVELOPMENT_TEAM=YOUR_TEAM_ID
```

## 注意

这套流程解决的是 TCC 身份稳定问题，不等于 notarization。应用仍然没有 Apple notarize 时，
首次打开可能需要右键打开、系统设置里允许打开，或手动移除 quarantine 属性。
