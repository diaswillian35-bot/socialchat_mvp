import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';


class OnlineDot extends StatelessWidget {
  final String uid;
  final double size; // tamanho da bolinha (ex: 10)
  final bool showBorder;


  const OnlineDot({
    super.key,
    required this.uid,
    this.size = 10,
    this.showBorder = true,
  });


  @override
  Widget build(BuildContext context) {
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);


    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userRef.snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? {};
        final isOnline = (data['isOnline'] == true);


        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: isOnline ? Colors.green : Colors.red,
            shape: BoxShape.circle,
            border: showBorder
                ? Border.all(color: Colors.white, width: 2)
                : null,
          ),
        );
      },
    );
  }
}
class AvatarWithOnlineDot extends StatelessWidget {
  final Widget avatar;
  final String uid;
  final double dotSize;


  const AvatarWithOnlineDot({
    super.key,
    required this.avatar,
    required this.uid,
    this.dotSize = 10,
  });


  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: -1,
          bottom: -1,
          child: OnlineDot(uid: uid, size: dotSize),
        ),
      ],
    );
  }
}
