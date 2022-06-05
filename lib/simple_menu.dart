import 'package:flutter/material.dart';

class SimpleMenuItem extends PopupMenuItem {
  final VoidCallback? innerOnTap;

  const SimpleMenuItem({
    required Widget child,
    VoidCallback? onTap,
    Key? key,
  })  : innerOnTap = onTap,
        super(child: child, key: key);

  @override
  VoidCallback? get onTap => () {
        if (super.onTap != null) {
          super.onTap!();
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (innerOnTap != null) {
            innerOnTap!();
          }
        });
      };
}

// TODO: wrap in StatefulWidget instead, but it doesn't really matter since _tapPos is short-lived
// ignore: must_be_immutable
class SimpleMenu extends GestureDetector {
  final BuildContext context;
  final List<SimpleMenuItem> items;

  Offset _tapPos = Offset.zero;

  SimpleMenu({required this.context, required this.items, required Widget child, Key? key})
      : super(key: key, child: child);

  void _showMenu() {
    final size = context.findRenderObject()?.paintBounds.size ?? Size.zero;
    showMenu(
      context: context,
      items: items,
      position: RelativeRect.fromRect(_tapPos & Size.zero, Offset.zero & size),
    );
  }

  @override
  get onTapDown => (details) => _tapPos = details.globalPosition;

  @override
  get onSecondaryTapDown => (details) => _tapPos = details.globalPosition;

  @override
  get onLongPress => () => _showMenu();

  @override
  get onSecondaryTap => () => _showMenu();
}
