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
