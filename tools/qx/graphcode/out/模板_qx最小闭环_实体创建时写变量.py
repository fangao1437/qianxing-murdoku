"""
graph_id: server_qx_min_loop_01
graph_name: 模板_qx最小闭环_实体创建时写变量
graph_type: server
description: qx 最小闭环：实体创建时 → 打印字符串 → 设置自定义变量（emit.mjs 生成，用于验证『代码能生成被接受的节点图』）
"""

import sys
from pathlib import Path

PROJECT_ROOT = next(p for p in Path(__file__).resolve().parents if (p / "assets" / "资源库").is_dir() or ((p / "engine").is_dir() and (p / "app").is_dir()))
sys.path.insert(0, str(PROJECT_ROOT))
sys.path.insert(1, str(PROJECT_ROOT / 'assets'))

from app.runtime.engine.graph_prelude_server import *  # noqa: F401,F403


class 模板_qx最小闭环_实体创建时写变量:
    def __init__(self, game, owner_entity):
        # 按上游约定：实例化即做静态校验，口径与编辑器一致。
        self.game = game
        self.owner_entity = owner_entity

        from app.runtime.engine.node_graph_validator import validate_node_graph

        validate_node_graph(self.__class__)

    def on_实体创建时(self, 事件源实体, 事件源GUID):
        # 触发器：实体创建时
        打印字符串(self.game, 字符串="qx-min-loop: entity created")
        设置自定义变量(self.game, 目标实体=事件源实体, 变量名="qx_min_loop_flag", 变量值=1, 是否触发事件=True)

    def register_handlers(self):
        self.game.register_event_handler("实体创建时", self.on_实体创建时, owner=self.owner_entity)


if __name__ == "__main__":
    from app.runtime.engine.node_graph_validator import validate_file_cli

    raise SystemExit(validate_file_cli(__file__))
