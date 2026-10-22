# Mahjong table styles

Settings → 牌桌主题 offers four local table finishes:

| Style | Surface |
| --- | --- |
| 海盐亚麻 | Blue-grey linen with fine warp and weft |
| 胡桃木纹 | Warm walnut with flowing, fine-grained growth lines |
| 酒红皮革 | Burgundy leather with subtle pebbling |
| 墨夜织锦 | Dark blue brocade with understated double diamond threads |

The selected style is stored in `mahjong.table.style`. A new installation or
unrecognized saved value uses 墨夜织锦 (brocade). Saved jade selections are
migrated to brocade. This preference belongs to the local player;
LAN guests can each choose their own finish.

The table and cached settings previews use the same SceneKit material shader.
Textures are procedural in world space, preserving pattern scale when the window
changes size. Changing a style updates only the surface material, without
recreating tiles, restarting a round, or modifying gameplay or network state.
