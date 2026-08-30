# Edit Mode — Technical Design

## 1. Overview

Edit Mode is a global app-state toggle that switches the entire app from **read-only / client mode** into **admin / edit mode**. It is a single boolean in a global service — one toggle, all screens flip together.

The toggle appears in the AppBar as a **pen icon** (currently read-only → tap to enter edit mode) or an **eye icon** (currently in edit mode → tap to return to read-only). It renders only when:
- The current screen participates in edit mode, AND
- The signed-in user holds at least one edit permission.

---

## 2. State — `EditModeService`

```
lib/state/edit_mode_service.dart
```

```dart
class EditModeService extends ChangeNotifier {
  bool _editMode = false;
  bool get isEditMode => _editMode;

  void toggle() {
    _editMode = !_editMode;
    notifyListeners();
  }

  void exit() {
    if (_editMode) { _editMode = false; notifyListeners(); }
  }
}
```

Registered as a top-level `ChangeNotifierProvider` in `main.dart` alongside the existing services.

---

## 3. AppBar Toggle Widget

```
lib/widgets/edit_mode_toggle.dart
```

`EditModeToggle` is an `IconButton` that watches `EditModeService`. Screens that support edit mode add it to their `AppBar.actions`:

```dart
actions: [
  if (context.watch<PermissionService>().canEditAnything)
    const EditModeToggle(),
],
```

`canEditAnything` is a convenience getter on `PermissionService` that returns true when the user holds any of: `EDIT_PRODUCTS`, `MANAGE_CATEGORIES`, `MANAGE_STORES`.

---

## 4. Edit Affordances

In edit mode, screens overlay a **pen icon** on each editable item (product tile, category tile, store row). Tapping the pen opens an **options bottom sheet** with "Edit [Item]" as its primary action. This bottom sheet is a stub for future additional actions (e.g. "Archive", "Duplicate").

---

## 5. Participating Screens

| Screen | Permission gating | Edit affordance | Opens |
|---|---|---|---|
| `BrowseScreen` (product list) | `EDIT_PRODUCTS` | Pen overlay on each product tile | `ProductEditScreen` |
| `CategoriesScreen` | `MANAGE_CATEGORIES` | Pen overlay on each category tile | `CategoryEditScreen` |
| `StorePicker` (store list) | `MANAGE_STORES` | Pen overlay on each store row | `StoreEditScreen` |
| `SettingsScreen` → Receipt Info section | `MANAGE_STORES` | Inline edit button | `ReceiptInfoEditScreen` |

---

## 6. Image Picker Flow

All avatar / logo fields use the same three-step flow:

### Step 1 — Source picker (bottom sheet)

`ResourcePickerSheet` appears with 3 options:

| Option | Action |
|---|---|
| Camera | `image_picker` camera capture |
| Gallery | `image_picker` gallery picker |
| Resource Manager | Open `ResourcePickerModal` |

### Step 2a — Camera / Gallery → Save Dialog

After picking a file from Camera or Gallery, `SaveResourceDialog` opens:

- **Directory** — dropdown populated from `GET /api/resources/{store}/directories`. Plus `+` button beside the dropdown: tapping it shows an inline text field to create a new directory on the fly (`POST /api/resources/{store}/directories`).
- **Filename** — text field, pre-filled with the original filename. User may rename.
- **Save** button — uploads via `POST /api/resources/{store}/assets?directory={id}&name={filename}`, returns `{ resource_id, public_url }`.

### Step 2b — Resource Manager modal

`ResourcePickerModal` — same two-panel directory + asset layout as Resource Explorer, but in a dialog. No upload/delete actions. Tapping any asset confirms selection and closes the modal, returning `{ resource_id, public_url }`.

### Step 3 — Caller receives result

Both paths produce the same result type:

```dart
class PickedResource {
  final int resourceId;
  final String publicUrl;
}
```

The caller patches its model with `resourceId` and immediately updates the UI with `publicUrl`.

---

## 7. Edit Screens

### 7a. `ProductEditScreen` (full-screen page)

**Route:** `Routes.productEdit` — receives product id as argument.

**Editable fields:**
- **Name** — bilingual text fields (Arabic + English), same pattern as existing i18n display_name fields
- **Description** — bilingual text areas
- **Avatar / Image** — tappable `CircleAvatar` / square image with pen icon; triggers full image picker flow (§6)

**Save:** `PATCH /api/products/{id}` — sends `{ displayName: {...}, description: {...}, imageResourceId }`.

---

### 7b. `CategoryEditScreen` (full-screen page)

**Editable fields:**
- **Name** — bilingual text fields
- **Avatar** — same picker flow (§6)

**Save:** `PATCH /api/categories/{id}` — sends `{ displayName: {...}, imageResourceId }`.

---

### 7c. `StoreEditScreen` (full-screen page)

Accessible from the pen overlay on each store row in `StorePicker`.

**Editable fields:**
- **Display name** — bilingual text fields
- **Avatar** — same picker flow (§6)

**Save:** `PATCH /api/stores/{id}` — sends `{ displayName: {...}, imageResourceId }`.

---

### 7d. `ReceiptInfoEditScreen` (full-screen page)

All receipt info fields are editable (not just the logo).

**Editable fields:**
- **Logo** — same picker flow (§6)
- **Store display name** (as shown on receipt)
- **Address line 1 / 2**
- **Phone**
- **Footer note / custom text**

**Save:** `PATCH /api/receipt-info` — sends all fields.

---

## 8. Backend — New Endpoints

All require the corresponding edit permission.

| Method | Path | Permission | Body |
|---|---|---|---|
| `PATCH` | `/api/products/{id}` | `EDIT_PRODUCTS` | `{ displayName, description, imageResourceId }` |
| `PATCH` | `/api/categories/{id}` | `MANAGE_CATEGORIES` | `{ displayName, imageResourceId }` |
| `PATCH` | `/api/stores/{id}` | `MANAGE_STORES` | `{ displayName, imageResourceId }` |
| `PATCH` | `/api/receipt-info` | `MANAGE_STORES` | all receipt fields |

All `displayName` / `description` fields are JSON i18n blobs: `{ "ar": "...", "en": "..." }`.

---

## 9. New Flutter Files Summary

```
lib/state/edit_mode_service.dart
lib/widgets/edit_mode_toggle.dart
lib/widgets/resource_picker_sheet.dart       ← 3-option source picker
lib/widgets/save_resource_dialog.dart        ← directory + filename + upload
lib/screens/resource_picker_modal.dart       ← browse + select existing asset
lib/screens/product_edit_screen.dart
lib/screens/category_edit_screen.dart
lib/screens/store_edit_screen.dart
lib/screens/receipt_info_edit_screen.dart
```

**Modified Flutter files:**
- `lib/main.dart` — register `EditModeService`
- `lib/state/permission_service.dart` — add `canEditAnything` getter
- `lib/screens/browse_screen.dart` — pen overlays on product tiles
- `lib/screens/categories_screen.dart` — pen overlays on category tiles
- `lib/screens/store_picker_screen.dart` — pen overlays on store rows
- `lib/screens/settings_screen.dart` — edit button in receipt info section
- `lib/router/app_router.dart` — new routes for all 4 edit screens
- `lib/services/api_client.dart` — PATCH methods for product, category, store, receipt

**New backend files (Spring Boot):**
- `ProductAdminController.java` (or extend existing controller)
- `CategoryAdminController.java`
- `StoreAdminController.java`
- `ReceiptInfoAdminController.java`

---

## 10. Implementation Order

1. `EditModeService` + `EditModeToggle` + wire into `main.dart` and `PermissionService`
2. `ResourcePickerSheet` + `SaveResourceDialog` (shared widget foundation)
3. `ResourcePickerModal` (select-only variant of explorer)
4. Backend PATCH endpoints (all 4)
5. `ProductEditScreen` + pen overlays on `BrowseScreen`
6. `CategoryEditScreen` + pen overlays on `CategoriesScreen`
7. `StoreEditScreen` + pen overlays on `StorePicker`
8. `ReceiptInfoEditScreen` + edit button in `SettingsScreen`
