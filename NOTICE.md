# 制作与来源

敲敲是一个本地桌面陪伴程序。macOS 使用 Swift / AppKit，Windows 使用 C# / WPF 与 Win32 Raw Input。源码由 Eiternal 发起制作，并在 AI 编程工具协助下实现。

小星狸角色和 48 张动画帧由 OpenAI 图像生成工具生成并经本项目处理。100 套装扮由代码绘制；Windows 中的装扮图层由同一份 macOS 绘制代码导出。生成式素材不代表对角色相似性的独占权利或保证。

逐帧曝光、短时 smear 和压力线条参考了 [Vincentwei1021/mg-styles-15](https://github.com/Vincentwei1021/mg-styles-15) 的 MIT 示例。本项目主体使用图片帧，参考仓库主体使用代码绘制。未使用该仓库的角色、影片或音频。

相关参考许可完整保存在 `macos/MG-STYLES-15-LICENSE.txt`，并随两个平台下载包一起提供。项目代码采用 MIT 许可，见 `LICENSE`。

Windows 运行包自带 Microsoft .NET Desktop Runtime；其中微软及其第三方组件遵循运行包内附带的许可。敲敲不附带分析统计 SDK、广告、在线账号服务或自动更新器。
