import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';

// MODELO DE DATOS
class Product {
  final int? id;
  final String nombre;
  final String marca;
  final String ubicacion;
  final String fotoPath;
  final double precioPaquete;
  final double precioUnidad;
  final int stock;

  Product({
    this.id,
    required this.nombre,
    required this.marca,
    required this.ubicacion,
    required this.fotoPath,
    this.precioPaquete = 0.0,
    this.precioUnidad = 0.0,
    this.stock = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nombre': nombre,
      'marca': marca,
      'ubicacion': ubicacion,
      'foto_path': fotoPath,
      'precio_paquete': precioPaquete,
      'precio_unidad': precioUnidad,
      'stock': stock,
    };
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'] as int?,
      nombre: map['nombre'] as String? ?? '',
      marca: map['marca'] as String? ?? '',
      ubicacion: map['ubicacion'] as String? ?? '',
      fotoPath: map['foto_path'] as String? ?? '',
      precioPaquete: (map['precio_paquete'] as num?)?.toDouble() ?? 0.0,
      precioUnidad: (map['precio_unidad'] as num?)?.toDouble() ?? 0.0,
      stock: map['stock'] as int? ?? 0,
    );
  }
}

// DATABASE HELPER
class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDb();
    return _database!;
  }

  Future<Database> _initDb() async {
    final path = p.join(await getDatabasesPath(), 'inventory.db');
    return openDatabase(
      path,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE productos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT,
        marca TEXT,
        ubicacion TEXT,
        foto_path TEXT,
        precio_paquete REAL DEFAULT 0.0,
        precio_unidad REAL DEFAULT 0.0,
        stock INTEGER DEFAULT 0
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE productos ADD COLUMN precio_paquete REAL DEFAULT 0.0');
      await db.execute('ALTER TABLE productos ADD COLUMN precio_unidad REAL DEFAULT 0.0');
      await db.execute('ALTER TABLE productos ADD COLUMN stock INTEGER DEFAULT 0');
    }
  }

  Future<int> insertProduct(Product product) async {
    final db = await database;
    return db.insert('productos', product.toMap());
  }

  Future<int> updateProduct(Product product) async {
    final db = await database;
    return db.update('productos', product.toMap(), where: 'id = ?', whereArgs: [product.id]);
  }

  Future<int> deleteProduct(int id) async {
    final db = await database;
    return db.delete('productos', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Product>> getProducts() async {
    final db = await database;
    final maps = await db.query('productos');
    return maps.map((map) => Product.fromMap(map)).toList();
  }
}

// PRODUCT PROVIDER
class ProductProvider with ChangeNotifier {
  List<Product> _products = [];
  List<Product> _filteredProducts = [];
  String _searchQuery = '';

  List<Product> get products => _filteredProducts;

  ProductProvider() {
    fetchProducts();
  }

  Future<void> fetchProducts() async {
    final dbHelper = DatabaseHelper();
    _products = await dbHelper.getProducts();
    _filterProducts();
    notifyListeners();
  }

  Future<void> addProduct(Product product) async {
    final dbHelper = DatabaseHelper();
    await dbHelper.insertProduct(product);
    await fetchProducts();
  }

  Future<void> updateProduct(Product product) async {
    final dbHelper = DatabaseHelper();
    await dbHelper.updateProduct(product);
    await fetchProducts();
  }

  Future<void> deleteProduct(int id) async {
    final dbHelper = DatabaseHelper();
    await dbHelper.deleteProduct(id);
    await fetchProducts();
  }

  void search(String query) {
    _searchQuery = query;
    _filterProducts();
    notifyListeners();
  }

  void _filterProducts() {
    if (_searchQuery.isEmpty) {
      _filteredProducts = List.from(_products);
    } else {
      final q = _searchQuery.toLowerCase();
      _filteredProducts = _products.where((p) =>
          p.nombre.toLowerCase().contains(q) ||
          p.marca.toLowerCase().contains(q)).toList();
    }
  }
}

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => ProductProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Inventario App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.grey[200],
        appBarTheme: const AppBarTheme(backgroundColor: Colors.blue, elevation: 4),
        cardTheme: CardTheme(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          filled: true,
          fillColor: Colors.white,
        ),
      ),
      home: const ProductListScreen(),
    );
  }
}

// PANTALLA PRINCIPAL (LISTA DE PRODUCTOS)
class ProductListScreen extends StatelessWidget {
  const ProductListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final productProvider = Provider.of<ProductProvider>(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Inventario')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              onChanged: (value) => productProvider.search(value),
              decoration: const InputDecoration(
                hintText: 'Buscar por nombre o marca...',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: Consumer<ProductProvider>(
              builder: (context, provider, child) {
                if (provider.products.isEmpty) {
                  return const Center(
                    child: Text('No hay productos. ¡Agrega uno!', style: TextStyle(fontSize: 18, color: Colors.grey)),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  itemCount: provider.products.length,
                  itemBuilder: (context, index) {
                    final product = provider.products[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8.0),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _showProductDetailModal(context, product),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8.0),
                                child: Image.file(
                                  File(product.fotoPath),
                                  width: 80,
                                  height: 80,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      width: 80,
                                      height: 80,
                                      color: Colors.grey.shade300,
                                      child: const Icon(Icons.inventory_2, color: Colors.white, size: 40),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(product.nombre, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 4),
                                    Text('Marca: ${product.marca}', style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Stock: ${product.stock}',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: product.stock > 0 ? Colors.green.shade700 : Colors.red.shade700,
                                          ),
                                        ),
                                        Text(
                                          '\$${product.precioUnidad.toStringAsFixed(2)}/u',
                                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue.shade800),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'edit') {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (context) => EditProductScreen(product: product)),
                                    );
                                  } else if (value == 'delete') {
                                    _showDeleteConfirmationDialog(context, product);
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(value: 'edit', child: Text('Editar')),
                                  const PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddProductScreen())),
        icon: const Icon(Icons.add),
        label: const Text('Agregar'),
        backgroundColor: Colors.blue.shade700,
      ),
    );
  }

  void _showProductDetailModal(BuildContext context, Product product) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(product.nombre, textAlign: TextAlign.center),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(product.fotoPath),
                  width: double.infinity,
                  height: 250,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 250,
                    color: Colors.grey.shade300,
                    child: const Icon(Icons.inventory_2, size: 80, color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('Marca: ${product.marca}', style: TextStyle(fontSize: 18, color: Colors.grey.shade700)),
              const SizedBox(height: 10),
              Text('Ubicación: ${product.ubicacion}', style: TextStyle(fontSize: 18, color: Colors.grey.shade700)),
              const SizedBox(height: 10),
              const Divider(),
              const SizedBox(height: 10),
              Text('Stock: ${product.stock} unidades', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Text('Precio Paquete: \$${product.precioPaquete.toStringAsFixed(2)}', style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 10),
              Text('Precio Unidad: \$${product.precioUnidad.toStringAsFixed(2)}', style: const TextStyle(fontSize: 18)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  void _showDeleteConfirmationDialog(BuildContext context, Product product) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Eliminación'),
        content: Text('¿Seguro que quieres eliminar "${product.nombre}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          TextButton(
            onPressed: () {
              Provider.of<ProductProvider>(context, listen: false).deleteProduct(product.id!);
              Navigator.pop(context);
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

// PANTALLA AGREGAR PRODUCTO
class AddProductScreen extends StatefulWidget {
  const AddProductScreen({super.key});

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _marcaController = TextEditingController();
  final _ubicacionController = TextEditingController();
  final _precioPaqueteController = TextEditingController();
  final _precioUnidadController = TextEditingController();
  final _stockController = TextEditingController();
  XFile? _imageFile;

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    try {
      final image = await picker.pickImage(source: ImageSource.camera);
      if (image != null) setState(() => _imageFile = image);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al tomar foto: $e')));
    }
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;
    if (_imageFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Toma una foto del producto')));
      return;
    }

    final appDir = await getApplicationDocumentsDirectory();
    final fileName = p.basename(_imageFile!.path);
    final savedPath = p.join(appDir.path, fileName);
    await File(_imageFile!.path).copy(savedPath);

    final newProduct = Product(
      nombre: _nombreController.text.trim(),
      marca: _marcaController.text.trim(),
      ubicacion: _ubicacionController.text.trim(),
      fotoPath: savedPath,
      precioPaquete: double.tryParse(_precioPaqueteController.text) ?? 0.0,
      precioUnidad: double.tryParse(_precioUnidadController.text) ?? 0.0,
      stock: int.tryParse(_stockController.text) ?? 0,
    );

    if (!mounted) return;
    Provider.of<ProductProvider>(context, listen: false).addProduct(newProduct);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Agregar Producto')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(controller: _nombreController, decoration: const InputDecoration(labelText: 'Nombre'), validator: (v) => v?.isEmpty ?? true ? 'Requerido' : null),
              const SizedBox(height: 16),
              TextFormField(controller: _marcaController, decoration: const InputDecoration(labelText: 'Marca'), validator: (v) => v?.isEmpty ?? true ? 'Requerido' : null),
              const SizedBox(height: 16),
              TextFormField(controller: _ubicacionController, decoration: const InputDecoration(labelText: 'Ubicación'), validator: (v) => v?.isEmpty ?? true ? 'Requerido' : null),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: TextFormField(controller: _precioPaqueteController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Precio Paquete'), validator: (v) => v?.isEmpty ?? true ? 'Requerido' : null)),
                  const SizedBox(width: 16),
                  Expanded(child: TextFormField(controller: _precioUnidadController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Precio Unidad'), validator: (v) => v?.isEmpty ?? true ? 'Requerido' : null)),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(controller: _stockController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Stock Inicial'), validator: (v) => v?.isEmpty ?? true ? 'Requerido' : null),
              const SizedBox(height: 32),
              Container(
                height: 200,
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey)),
                child: _imageFile == null
                    ? const Center(child: Text('No has tomado foto'))
                    : ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(File(_imageFile!.path), fit: BoxFit.cover)),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(onPressed: _pickImage, icon: const Icon(Icons.camera_alt), label: const Text('Tomar Foto'), style: ElevatedButton.styleFrom(backgroundColor: Colors.teal)),
              const SizedBox(height: 32),
              ElevatedButton(onPressed: _saveProduct, child: const Text('Guardar')),
            ],
          ),
        ),
      ),
    );
  }
}

// PANTALLA EDITAR PRODUCTO (similar a agregar, pero pre-cargada)
class EditProductScreen extends StatefulWidget {
  final Product product;
  const EditProductScreen({super.key, required this.product});

  @override
  State<EditProductScreen> createState() => _EditProductScreenState();
}

class _EditProductScreenState extends State<EditProductScreen> {
  late TextEditingController _nombreController;
  late TextEditingController _marcaController;
  late TextEditingController _ubicacionController;
  late TextEditingController _precioPaqueteController;
  late TextEditingController _precioUnidadController;
  late TextEditingController _stockController;
  final _formKey = GlobalKey<FormState>();
  XFile? _imageFile;

  @override
  void initState() {
    super.initState();
    _nombreController = TextEditingController(text: widget.product.nombre);
    _marcaController = TextEditingController(text: widget.product.marca);
    _ubicacionController = TextEditingController(text: widget.product.ubicacion);
    _precioPaqueteController = TextEditingController(text: widget.product.precioPaquete.toStringAsFixed(2));
    _precioUnidadController = TextEditingController(text: widget.product.precioUnidad.toStringAsFixed(2));
    _stockController = TextEditingController(text: widget.product.stock.toString());
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    try {
      final image = await picker.pickImage(source: ImageSource.camera);
      if (image != null) setState(() => _imageFile = image);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al tomar foto: $e')));
    }
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    String imagePath = widget.product.fotoPath;
    if (_imageFile != null) {
      final appDir = await getApplicationDocumentsDirectory();
      final fileName = p.basename(_imageFile!.path);
      imagePath = p.join(appDir.path, fileName);
      await File(_imageFile!.path).copy(imagePath);
    }

    final updated = Product(
      id: widget.product.id,
      nombre: _nombreController.text.trim(),
      marca: _marcaController.text.trim(),
      ubicacion: _ubicacionController.text.trim(),
      fotoPath: imagePath,
      precioPaquete: double.tryParse(_precioPaqueteController.text) ?? 0.0,
      precioUnidad: double.tryParse(_precioUnidadController.text) ?? 0.0,
      stock: int.tryParse(_stockController.text) ?? 0,
    );

    if (!mounted) return;
    Provider.of<ProductProvider>(context, listen: false).updateProduct(updated);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Editar Producto')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(controller: _nombreController, decoration: const InputDecoration(labelText: 'Nombre'), validator: (v) => v?.isEmpty ?? true ? 'Requerido' : null),
              const SizedBox(height: 16),
              TextFormField(controller: _marcaController, decoration: const InputDecoration(labelText: 'Marca'), validator: (v) => v?.isEmpty ?? true ? 'Requerido' : null),
              const SizedBox(height: 16),
              TextFormField(controller: _ubicacionController, decoration: const InputDecoration(labelText: 'Ubicación'), validator: (v) => v?.isEmpty ?? true ? 'Requerido' : null),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: TextFormField(controller: _precioPaqueteController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Precio Paquete'), validator: (v) => v?.isEmpty ?? true ? 'Requerido' : null)),
                  const SizedBox(width: 16),
                  Expanded(child: TextFormField(controller: _precioUnidadController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Precio Unidad'), validator: (v) => v?.isEmpty ?? true ? 'Requerido' : null)),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(controller: _stockController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Stock'), validator: (v) => v?.isEmpty ?? true ? 'Requerido' : null),
              const SizedBox(height: 32),
              Container(
                height: 200,
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey)),
                child: _imageFile != null
                    ? ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(File(_imageFile!.path), fit: BoxFit.cover))
                    : ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(File(widget.product.fotoPath), fit: BoxFit.cover)),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(onPressed: _pickImage, icon: const Icon(Icons.camera_alt), label: const Text('Cambiar Foto'), style: ElevatedButton.styleFrom(backgroundColor: Colors.teal)),
              const SizedBox(height: 32),
              ElevatedButton(onPressed: _saveChanges, child: const Text('Guardar Cambios')),
            ],
          ),
        ),
      ),
    );
  }
}