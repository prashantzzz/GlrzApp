import 'package:aves/model/settings/settings.dart';
import 'package:aves/widgets/common/fx/borders.dart';
import 'package:aves/widgets/common/fx/colors.dart';
import 'package:aves_model/aves_model.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AvesLogo extends StatelessWidget {
  final double size;

  const AvesLogo({
    super.key,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      backgroundColor: Colors.white,
      radius: size / 2,
      child: Padding(
        padding: EdgeInsets.all(size / 10),
        child: Image.asset(
          'assets/GalleryzeIcon.png',
          width: size,
          height: size,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

