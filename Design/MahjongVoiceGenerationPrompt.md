# 麻将完整男女声生成提示词

请为一款休闲麻将游戏批量生成**两套彼此独立的普通话语音**：女声 48 条、男声 48 条。每套内保持同一位说话人、同一音色、相近音量与语速；男女声都要自然、清楚、有轻微游戏互动感，避免播音腔、夸张表演和模仿真人。女声温暖明亮，男声沉稳亲切。所有音频只读“台词”列的文字，不读文件名、标点或额外说明。

每条台词单独导出一个文件，目录分别为 `Resources/MahjongAudio/female/` 和 `Resources/MahjongAudio/male/`，两个目录的文件名完全相同。优先导出单声道 MP3，采样率 44.1 或 48 kHz，码率至少 128 kbps；也可导出同名 M4A。游戏优先播放同名 MP3，因此若用 M4A 替换旧配音，须移除对应的旧 MP3。不要加入音乐、音效、混响或环境噪声。首尾仅保留约 50–100 毫秒自然空白，整体音量一致，避免削波。单字口令干脆有力；牌名和加倍口令尽量控制在约 1 秒内。多音字按麻将语境发音：“胡了”读 hú le，“条”读 tiáo，“筒”读 tǒng。

严格按下面的**文件名 → 台词**清单输出，每个性别各一份，共 96 个文件。`action-kong` 是通用“杠”素材，一并保留；其余所有项目均为游戏当前会调用的播报。

| 文件名（不含扩展名） | 台词 |
| --- | --- |
| `tile-characters-1` | 一万 |
| `tile-characters-2` | 二万 |
| `tile-characters-3` | 三万 |
| `tile-characters-4` | 四万 |
| `tile-characters-5` | 五万 |
| `tile-characters-6` | 六万 |
| `tile-characters-7` | 七万 |
| `tile-characters-8` | 八万 |
| `tile-characters-9` | 九万 |
| `tile-dots-1` | 一筒 |
| `tile-dots-2` | 二筒 |
| `tile-dots-3` | 三筒 |
| `tile-dots-4` | 四筒 |
| `tile-dots-5` | 五筒 |
| `tile-dots-6` | 六筒 |
| `tile-dots-7` | 七筒 |
| `tile-dots-8` | 八筒 |
| `tile-dots-9` | 九筒 |
| `tile-bamboo-1` | 一条 |
| `tile-bamboo-2` | 二条 |
| `tile-bamboo-3` | 三条 |
| `tile-bamboo-4` | 四条 |
| `tile-bamboo-5` | 五条 |
| `tile-bamboo-6` | 六条 |
| `tile-bamboo-7` | 七条 |
| `tile-bamboo-8` | 八条 |
| `tile-bamboo-9` | 九条 |
| `tile-honor-0` | 东风 |
| `tile-honor-1` | 南风 |
| `tile-honor-2` | 西风 |
| `tile-honor-3` | 北风 |
| `tile-honor-4` | 红中 |
| `tile-honor-5` | 发财 |
| `tile-honor-6` | 白板 |
| `action-chi` | 吃 |
| `action-pong` | 碰 |
| `action-kong` | 杠 |
| `action-exposed-kong` | 明杠 |
| `action-concealed-kong` | 暗杠 |
| `action-added-kong` | 补杠 |
| `action-win` | 胡了 |
| `action-self-draw` | 自摸 |
| `action-draw` | 流局 |
| `action-pass` | 过 |
| `action-missing-suit` | 定缺 |
| `action-no-double` | 不加倍 |
| `action-double` | 加倍 |
| `action-super-double` | 超级加倍 |

交付前逐项检查：每套 48 个文件；台词与文件名一一对应；无漏字、口误、爆音或多余空白；男女声相同台词的节奏和响度接近。若生成平台不能批量命名，请连同每个音频返回对应文件名，不要合并成一段长录音。
