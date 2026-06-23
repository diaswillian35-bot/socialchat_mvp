import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../l10n/app_texts.dart';

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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedDate == null || _selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escolha data e horário')),
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
      const SnackBar(
        content: Text('Evento enviado novamente para aprovação'),
      ),
    );

    Navigator.pop(context);
  }

  String _dateText() {
    if (_selectedDate == null) return 'Escolher data';

    final d = _selectedDate!;
    String two(int n) => n.toString().padLeft(2, '0');

    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }

  String _timeText() {
    if (_selectedTime == null) return 'Escolher horário';

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
        title: const Text(
          'Editar evento',
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
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Edite seu evento. Após salvar, ele será enviado novamente para aprovação.',
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
                  hint: 'Título do evento',
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Digite o título';
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
                  hint: 'Cidade',
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Digite a cidade';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 14),

                _field(
                  controller: _placeController,
                  hint: 'Local',
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

                const SizedBox(height: 14),

                _field(
                  controller: _descriptionController,
                  hint: 'Descrição',
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
                    title: const Text(
                      'Quer destacar seu evento?',
                      style: TextStyle(
                        color: _text,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    subtitle: const Text(
                      'Tenho interesse em patrocínio',
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
                        : const Text(
                            'Salvar alterações',
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
