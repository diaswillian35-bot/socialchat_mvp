import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../l10n/app_texts.dart';
import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

class EditEventPage extends StatefulWidget {
  final String eventId;

  const EditEventPage({
    super.key,
    required this.eventId,
  });

  @override
  State<EditEventPage> createState() => _EditEventPageState();
}

class _EditEventPageState extends State<EditEventPage> {
  static const Color _remdyBlue = Color(0xFF313A5F);
  static const Color _bg = Color(0xFFF6F7FB);
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);

  final _formKey = GlobalKey<FormState>();

  final _titleController = TextEditingController();
  final _cityController = TextEditingController();
  final _placeController = TextEditingController();
  final _descriptionController = TextEditingController();

  String _category = 'Geral';
  bool _sponsorInterested = false;

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  bool _loading = true;
  bool _saving = false;
 
final ImagePicker _picker = ImagePicker();

List<String> _photoUrls = [];
String _coverUrl = '';
bool _uploadingPhoto = false;


  final List<String> _categories = const [
    'Geral',
    'Música',
    'Esportes',
    'Restaurante',
    'Cultura',
    'Idiomas',
  ];

  @override
  void initState() {
    super.initState();
    _loadEvent();
  }

  Future<void> _loadEvent() async {
    final doc = await FirebaseFirestore.instance
        .collection('events')
        .doc(widget.eventId)
        .get();

    if (!doc.exists) {
      if (!mounted) return;
      Navigator.pop(context);
      return;
    }

    final data = doc.data()!;

    final savedCategory = (data['category'] ?? 'Geral').toString();

    final startAt = data['startAt'];
    DateTime? eventDate;

    if (startAt is Timestamp) {
      eventDate = startAt.toDate();
    }

    setState(() {
      _titleController.text = (data['title'] ?? '').toString();
      _cityController.text = (data['city'] ?? '').toString();
      _placeController.text = (data['placeName'] ?? '').toString();
      _descriptionController.text = (data['description'] ?? '').toString();

      _category =
          _categories.contains(savedCategory) ? savedCategory : 'Geral';

      _sponsorInterested = data['sponsorInterested'] == true;
_photoUrls = (data['photoUrls'] is List)
    ? List<String>.from((data['photoUrls'] as List).map((e) => e.toString()))
    : <String>[];

_coverUrl = (data['coverUrl'] ?? '').toString();

      if (eventDate != null) {
        _selectedDate = DateTime(
          eventDate.year,
          eventDate.month,
          eventDate.day,
        );
        _selectedTime = TimeOfDay(
          hour: eventDate.hour,
          minute: eventDate.minute,
        );
      }

      _loading = false;
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();

    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: now,
      lastDate: DateTime(now.year + 2),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: _remdyBlue,
            ),
          ),
          child: child!,
        );
      },
    );

    if (date != null) {
      setState(() => _selectedDate = date);
    }
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: _remdyBlue,
            ),
          ),
          child: child!,
        );
      },
    );

    if (time != null) {
      setState(() => _selectedTime = time);
    }
  }

Future<void> _addPhoto() async {
  if (_photoUrls.length >= 5) {
    ScaffoldMessenger.of(context).showSnackBar(
   SnackBar(content: Text(AppTexts.current.get('max_5_photos')))
    );
    return;
  }

  final picked = await _picker.pickImage(
    source: ImageSource.gallery,
    imageQuality: 82,
  );

  if (picked == null) return;

  setState(() => _uploadingPhoto = true);

  try {
    final file = File(picked.path);

    final ref = FirebaseStorage.instance
        .ref()
        .child('events')
        .child(widget.eventId)
        .child('photos')
        .child('${DateTime.now().millisecondsSinceEpoch}.jpg');

    await ref.putFile(file);
    final url = await ref.getDownloadURL();

    setState(() {
      _photoUrls.add(url);
      if (_coverUrl.isEmpty) _coverUrl = url;
    });
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
     SnackBar(content: Text('${AppTexts.current.get('photo_upload_error')}: $e'))
    );
  } finally {
    if (mounted) setState(() => _uploadingPhoto = false);
  }
}


Future<void> _removePhoto(String url) async {
  final removedCover = (_coverUrl == url);

  setState(() {
    _photoUrls.remove(url);

    if (removedCover) {
      _coverUrl = _photoUrls.isNotEmpty ? _photoUrls.first : '';
    }
  });

  try {
    await FirebaseStorage.instance.refFromURL(url).delete();
  } catch (_) {}

  await FirebaseFirestore.instance
      .collection('events')
      .doc(widget.eventId)
      .update({
    'photoUrls': _photoUrls,
    'coverUrl': _coverUrl,
  });
}



  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedDate == null || _selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
     SnackBar(content: Text(AppTexts.current.get('choose_date_time'))),
      );
      return;
    }

    setState(() => _saving = true);

    final startAt = DateTime(
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
      _selectedTime!.hour,
      _selectedTime!.minute,
    );

    await FirebaseFirestore.instance
        .collection('events')
        .doc(widget.eventId)
        .set({
      'title': _titleController.text.trim(),
      'city': _cityController.text.trim(),
      'cityKey': _cityController.text.trim().toLowerCase(),
      'placeName': _placeController.text.trim(),
      'description': _descriptionController.text.trim(),
      'category': _category,
      'photoUrls': _photoUrls,
'coverUrl': _coverUrl,
      'sponsorInterested': _sponsorInterested,
      'startAt': Timestamp.fromDate(startAt),

      // volta para aprovação
      'status': 'pending',
      'isActive': false,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!mounted) return;

    setState(() => _saving = false);

    ScaffoldMessenger.of(context).showSnackBar(
       SnackBar(
       content: Text(AppTexts.current.get('event_sent_for_approval')),

      ),
    );

    Navigator.pop(context);
  }

  String _dateText() {
  if (_selectedDate == null) return AppTexts.current.get('choose_date');

    final d = _selectedDate!;
    String two(int n) => n.toString().padLeft(2, '0');

    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }

  String _timeText() {
  if (_selectedTime == null) return AppTexts.current.get('choose_time');


    String two(int n) => n.toString().padLeft(2, '0');

    return '${two(_selectedTime!.hour)}:${two(_selectedTime!.minute)}';
  }

  Widget _field({
    required TextEditingController controller,
    required String hint,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        validator: validator,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(
            color: _muted,
            fontWeight: FontWeight.w600,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 18,
          ),
        ),
      ),
    );
  }

  Widget _dateButton({
    required IconData icon,
    required String text,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: _border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: _muted),
              const SizedBox(width: 8),
              Text(
                text,
                style: const TextStyle(
                  color: _muted,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _cityController.dispose();
    _placeController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current.get;

    if (_loading) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(
          child: CircularProgressIndicator(color: _remdyBlue),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        surfaceTintColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _text),
         title: Text(
  t('edit_event'),

          style: TextStyle(
            color: _text,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                 Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    t('edit_event_info'),
                    style: TextStyle(
                      color: _muted,
                      fontSize: 15,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

                const SizedBox(height: 18),

            _field(
  controller: _titleController,
  hint: t('event_title'),
  validator: (v) {
    if (v == null || v.trim().isEmpty) {
      return t('enter_event_title');
    }
    return null;
  },
),


                const SizedBox(height: 14),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _category,
                      isExpanded: true,
                      borderRadius: BorderRadius.circular(18),
                      icon: const Icon(Icons.keyboard_arrow_down),
                      items: _categories.map((cat) {
                        return DropdownMenuItem(
                          value: cat,
                          child: Text(
                            cat,
                            style: const TextStyle(
                              color: _text,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _category = value);
                        }
                      },
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                _field(
                  controller: _cityController,
                  hint: t('city'),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return t('enter_city');
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 14),

                _field(
                  controller: _placeController,
               
hint: t('place'),

                ),

                const SizedBox(height: 14),

                Row(
                  children: [
                    _dateButton(
                      icon: Icons.calendar_month_outlined,
                      text: _dateText(),
                      onTap: _pickDate,
                    ),
                    const SizedBox(width: 10),
                    _dateButton(
                      icon: Icons.access_time,
                      text: _timeText(),
                      onTap: _pickTime,
                    ),
                  ],
                ),

if (_photoUrls.isNotEmpty || _uploadingPhoto) ...[
  Wrap(
    spacing: 10,
    runSpacing: 10,
    children: [
      ..._photoUrls.map(
        (url) => Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.network(
                url,
                width: 110,
                height: 110,
                fit: BoxFit.cover,
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: InkWell(
                onTap: () => _removePhoto(url),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(4),
                  child: const Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ),
            
Positioned(
  top: 4,
  left: 4,
  child: InkWell(
    onTap: () {
      setState(() => _coverUrl = url);
    },
    child: Container(
      decoration: BoxDecoration(
        color: _coverUrl == url ? _remdyBlue : Colors.black54,
        shape: BoxShape.circle,
      ),
      padding: const EdgeInsets.all(5),
      child: Icon(
        _coverUrl == url ? Icons.star : Icons.star_border,
        color: Colors.white,
        size: 18,
      ),
    ),
  ),
),


          ],
        ),
      ),

      if (_photoUrls.length < 5)
        InkWell(
          onTap: _uploadingPhoto ? null : _addPhoto,
          child: Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              border: Border.all(color: _border),
              borderRadius: BorderRadius.circular(14),
            ),
            child: _uploadingPhoto
                ? const Center(
                    child: CircularProgressIndicator(),
                  )
               
: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const Icon(Icons.add_a_photo_outlined),
      const SizedBox(height: 8),
      Text(t('add_photo')),
    ],
  ),

          ),
        ),
    ],
  ),
  const SizedBox(height: 14),
],


                const SizedBox(height: 14),

                _field(
                  controller: _descriptionController,
                hint: t('description'),
                  maxLines: 5,
                ),

                const SizedBox(height: 14),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _border),
                  ),
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _sponsorInterested,
                    activeColor: _remdyBlue,
                   
title: Text(
  t('highlight_event'),

                      style: TextStyle(
                        color: _text,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                   subtitle: Text(
  t('sponsor_interest'),

                      style: TextStyle(
                        color: _muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onChanged: (value) {
                      setState(() => _sponsorInterested = value);
                    },
                  ),
                ),

                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _remdyBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : Text(
  t('save_changes'),

                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
