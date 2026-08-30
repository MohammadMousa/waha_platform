import 'package:flutter/material.dart';

class EditModeService extends ChangeNotifier {
  bool _editMode = false;
  bool get isEditMode => _editMode;

  void toggle() {
    _editMode = !_editMode;
    notifyListeners();
  }

  void exit() {
    if (_editMode) {
      _editMode = false;
      notifyListeners();
    }
  }
}

final editModeService = EditModeService();
