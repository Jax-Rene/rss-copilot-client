import 'package:flutter/material.dart';

class ResponsiveHomeShell extends StatelessWidget {
  const ResponsiveHomeShell({
    super.key,
    required this.navigationPane,
    required this.listPane,
    required this.detailPane,
    required this.mobileBody,
  });

  final Widget navigationPane;
  final Widget listPane;
  final Widget detailPane;
  final Widget mobileBody;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 1000) {
          return Row(
            key: const Key('desktop-shell'),
            children: [
              SizedBox(width: 96, child: navigationPane),
              const VerticalDivider(width: 1),
              SizedBox(width: 420, child: listPane),
              const VerticalDivider(width: 1),
              Expanded(child: detailPane),
            ],
          );
        }

        return Container(
          key: const Key('mobile-shell'),
          color: Theme.of(context).scaffoldBackgroundColor,
          child: mobileBody,
        );
      },
    );
  }
}
