import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/edit_mode_service.dart';

class EditModeToggle extends StatelessWidget {
  const EditModeToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final editMode = context.watch<EditModeService>();
    return IconButton(
      tooltip: editMode.isEditMode ? 'Exit edit mode' : 'Enter edit mode',
      icon: Icon(
        editMode.isEditMode ? Icons.visibility_outlined : Icons.edit_outlined,
      ),
      onPressed: editMode.toggle,
    );
  }
}
