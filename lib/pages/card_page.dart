import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';


class CardPage extends StatefulWidget {
  const CardPage({super.key});


  @override
  State<CardPage> createState() => _CardPageState();
}


class _CardPageState extends State<CardPage> {
  final _nameC = TextEditingController();
  final _numberC = TextEditingController();
  final _expiryC = TextEditingController();
  final _cvvC = TextEditingController();


  bool _loading = false;


  // Remdy colors (iguais ao teu Premium)
  static const Color _bg = Color(0xFFF8FAFC);
  static const Color _card = Colors.white;
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _remdyBlue = Color(0xFF313A5F);


  String _brand = 'Card';
  String _previewMasked = '•••• •••• •••• ••••';
  String _previewExp = 'MM/AA';
  String _previewName = 'NOME NO CARTÃO';


  String? _error;


  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';


  @override
  void initState() {
    super.initState();


    _numberC.addListener(() {
      final raw = _digitsOnly(_numberC.text);
      _brand = _detectBrand(raw);
      _previewMasked = _maskCard(raw);
      setState(() {});
    });


    _expiryC.addListener(() {
      _previewExp = _expiryC.text.isEmpty ? 'MM/AA' : _expiryC.text;
      setState(() {});
    });


    _nameC.addListener(() {
      _previewName = _nameC.text.trim().isEmpty ? 'NOME NO CARTÃO' : _nameC.text.trim().toUpperCase();
      setState(() {});
    });
  }


  @override
  void dispose() {
    _nameC.dispose();
    _numberC.dispose();
    _expiryC.dispose();
    _cvvC.dispose();
    super.dispose();
  }


  String _digitsOnly(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');


  String _detectBrand(String digits) {
    if (digits.isEmpty) return 'Card';
    // Regras simples (não precisa ser perfeito)
    if (digits.startsWith('4')) return 'VISA';
    if (digits.startsWith('5')) return 'MASTERCARD';
    if (digits.startsWith('34') || digits.startsWith('37')) return 'AMEX';
    if (digits.startsWith('6')) return 'DISCOVER';
    return 'CARD';
  }


  String _maskCard(String digits) {
    if (digits.isEmpty) return '•••• •••• •••• ••••';
    final last4 = digits.length <= 4 ? digits : digits.substring(digits.length - 4);
    return '•••• •••• •••• $last4';
  }


  bool _luhnValid(String digits) {
    if (digits.length < 12) return false;
    int sum = 0;
    bool alt = false;
    for (int i = digits.length - 1; i >= 0; i--) {
      int n = int.parse(digits[i]);
      if (alt) {
        n *= 2;
        if (n > 9) n -= 9;
      }
      sum += n;
      alt = !alt;
    }
    return sum % 10 == 0;
  }


  /// Expira no formato MM/AA ou MM/AAAA
  bool _expiryValid(String exp) {
    final clean = exp.trim();
    final parts = clean.split('/');
    if (parts.length != 2) return false;


    final mm = int.tryParse(parts[0]) ?? -1;
    if (mm < 1 || mm > 12) return false;


    int yy = int.tryParse(parts[1]) ?? -1;
    if (yy < 0) return false;
    if (parts[1].length == 2) yy += 2000;
    if (yy < 2000 || yy > 2100) return false;


    final now = DateTime.now();
    final endOfMonth = DateTime(yy, mm + 1, 0, 23, 59, 59);
    return endOfMonth.isAfter(now);
  }


  Map<String, int>? _parseExpiry(String exp) {
    final parts = exp.trim().split('/');
    if (parts.length != 2) return null;


    final mm = int.tryParse(parts[0]) ?? -1;
    int yy = int.tryParse(parts[1]) ?? -1;
    if (mm < 1 || mm > 12) return null;
    if (yy < 0) return null;
    if (parts[1].length == 2) yy += 2000;
    return {'month': mm, 'year': yy};
  }


  Future<void> _saveCard() async {
    setState(() => _error = null);


    if (_uid.isEmpty) {
      setState(() => _error = 'Você precisa estar logado.');
      return;
    }


    final name = _nameC.text.trim();
    final numberDigits = _digitsOnly(_numberC.text);
    final expiry = _expiryC.text.trim();
    final cvvDigits = _digitsOnly(_cvvC.text);


    if (name.length < 3) {
      setState(() => _error = 'Digite o nome do cartão.');
      return;
    }
    if (!_luhnValid(numberDigits)) {
      setState(() => _error = 'Número do cartão inválido.');
      return;
    }
    if (!_expiryValid(expiry)) {
      setState(() => _error = 'Validade inválida. Use MM/AA.');
      return;
    }
    if (cvvDigits.length < 3 || cvvDigits.length > 4) {
      setState(() => _error = 'CVV inválido.');
      return;
    }


    final expParsed = _parseExpiry(expiry);
    if (expParsed == null) {
      setState(() => _error = 'Validade inválida.');
      return;
    }


    // ✅ Só salva dados NÃO sensíveis
    final last4 = numberDigits.substring(numberDigits.length - 4);
    final brand = _detectBrand(numberDigits);


    setState(() => _loading = true);


    try {
      final db = FirebaseFirestore.instance;


      // Salva como "cartão principal" no user (simples)
      await db.collection('users').doc(_uid).set({
        'paymentMethod': {
          'brand': brand,
          'last4': last4,
          'expMonth': expParsed['month'],
          'expYear': expParsed['year'],
          'holderName': name,
          'updatedAt': FieldValue.serverTimestamp(),
        }
      }, SetOptions(merge: true));


      if (!mounted) return;


      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cartão salvo ✅'),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.all(12),
          duration: Duration(seconds: 1),
        ),
      );


      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Erro ao salvar: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    const overlay = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light, // iOS
    );


    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          systemOverlayStyle: overlay,
          iconTheme: const IconThemeData(color: _text),
          title: const Text(
            'Adicionar cartão',
            style: TextStyle(color: _text, fontWeight: FontWeight.w900),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            // Preview do cartão
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _border),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0A000000),
                    blurRadius: 14,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Text(
                          _brand,
                          style: const TextStyle(fontWeight: FontWeight.w900, color: _text),
                        ),
                      ),
                      const Spacer(),
                      const Icon(Icons.credit_card, color: _remdyBlue),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _previewMasked,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.1,
                      color: _text,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _previewName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: _muted,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _previewExp,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: _text,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),


            const SizedBox(height: 14),


            if (_error != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F2),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xFF991B1B),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),


            if (_error != null) const SizedBox(height: 12),


            _field(
              label: 'Nome no cartão',
              controller: _nameC,
              hint: 'Ex: WILLIAN DIAS',
              textInputAction: TextInputAction.next,
              keyboardType: TextInputType.name,
            ),
            _field(
              label: 'Número do cartão',
              controller: _numberC,
              hint: '0000 0000 0000 0000',
              textInputAction: TextInputAction.next,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')),
                LengthLimitingTextInputFormatter(19),
                _CardNumberFormatter(),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: _field(
                    label: 'Validade',
                    controller: _expiryC,
                    hint: 'MM/AA',
                    textInputAction: TextInputAction.next,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                      _ExpiryFormatter(),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _field(
                    label: 'CVV',
                    controller: _cvvC,
                    hint: '123',
                    textInputAction: TextInputAction.done,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                  ),
                ),
              ],
            ),


            const SizedBox(height: 16),


            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: _remdyBlue,
              ),
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _saveCard,
                icon: const Icon(Icons.lock, size: 18),
                label: Text(
                  _loading ? 'Salvando...' : 'Salvar cartão',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),


            const SizedBox(height: 12),


            const Text(
              'Segurança: o app NÃO salva número completo nem CVV. Apenas bandeira, últimos 4 e validade.',
              style: TextStyle(
                fontSize: 12,
                color: _muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _field({
    required String label,
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w900, color: _text),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            inputFormatters: inputFormatters,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: _muted, fontWeight: FontWeight.w600),
              filled: true,
              fillColor: _card,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: _border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: _remdyBlue, width: 1.2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class _CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final buffer = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      buffer.write(digits[i]);
      final idx = i + 1;
      if (idx % 4 == 0 && idx != digits.length) buffer.write(' ');
    }
    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}


class _ExpiryFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(text: '');
    }
    String text;
    if (digits.length <= 2) {
      text = digits;
    } else {
      text = '${digits.substring(0, 2)}/${digits.substring(2, digits.length)}';
    }
    if (text.length > 5) text = text.substring(0, 5);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
