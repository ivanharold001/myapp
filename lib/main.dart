import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

// --- MODELOS DE DATOS ---

enum VentaEstado { PENDIENTE, COMPLETADA }

class Product {
  final int? id;
  final String nombre;
  final String marca;
  final String ubicacion;
  final int unidadesPorPaquete; // <-- CAMPO NUEVO Y CRUCIAL
  int stock;
  final double precioPaquete;
  final double precioUnidad;
  final List<String> fotoPaths;

  Product({
    this.id,
    required this.nombre,
    required this.marca,
    required this.ubicacion,
    required this.unidadesPorPaquete, // <-- AÑADIDO
    required this.stock,
    required this.precioPaquete,
    required this.precioUnidad,
    this.fotoPaths = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nombre': nombre,
      'marca': marca,
      'ubicacion': ubicacion,
      'unidades_por_paquete': unidadesPorPaquete, // <-- AÑADIDO
      'stock': stock,
      'precio_paquete': precioPaquete,
      'precio_unidad': precioUnidad,
    };
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'],
      nombre: map['nombre'],
      marca: map['marca'],
      ubicacion: map['ubicacion'],
      unidadesPorPaquete: map['unidades_por_paquete'] ?? 1, // <-- AÑADIDO
      stock: map['stock'] ?? 0,
      precioPaquete: (map['precio_paquete'] as num?)?.toDouble() ?? 0.0,
      precioUnidad: (map['precio_unidad'] as num?)?.toDouble() ?? 0.0,
    );
  }

   Product copyWith({List<String>? fotoPaths, int? stock}) {
    return Product(
      id: id,
      nombre: nombre,
      marca: marca,
      ubicacion: ubicacion,
      unidadesPorPaquete: unidadesPorPaquete,
      stock: stock ?? this.stock,
      precioPaquete: precioPaquete,
      precioUnidad: precioUnidad,
      fotoPaths: fotoPaths ?? this.fotoPaths,
    );
  }
}

// NUEVO MODELO PARA LOS ITEMS DE LA VENTA
class VentaItem {
  final int? id;
  final int ventaId;
  final Product producto;
  final int cantidad;
  final double precioVenta;
  final bool esPorPaquete;
  bool verificado;

  VentaItem({
    this.id,
    required this.ventaId,
    required this.producto,
    required this.cantidad,
    required this.precioVenta,
    required this.esPorPaquete,
    this.verificado = false,
  });

   Map<String, dynamic> toMap() {
    return {
      'id': id,
      'venta_id': ventaId,
      'producto_id': producto.id,
      'cantidad': cantidad,
      'precio_venta': precioVenta,
      'es_por_paquete': esPorPaquete ? 1 : 0,
      'verificado': verificado ? 1 : 0,
    };
  }
}

// NUEVO MODELO PARA LA VENTA
class Venta {
  final int? id;
  final String nombreCliente;
  final String telefonoCliente;
  final DateTime fecha;
  final double total;
  final VentaEstado estado;
  final List<VentaItem> items;

  Venta({
    this.id,
    required this.nombreCliente,
    required this.telefonoCliente,
    required this.fecha,
    required this.total,
    this.estado = VentaEstado.PENDIENTE,
    this.items = const [],
  });

   Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nombre_cliente': nombreCliente,
      'telefono_cliente': telefonoCliente,
      'fecha': fecha.toIso8601String(),
      'total': total,
      'estado': estado.toString().split('.').last,
    };
  }
}

// --- DATABASE HELPER ---
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
    String path = p.join(await getDatabasesPath(), 'inventory.db');
    return await openDatabase(
      path,
      version: 5, // <-- VERSIÓN INCREMENTADA A 5
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
        unidades_por_paquete INTEGER NOT NULL,
        stock INTEGER,
        precio_paquete REAL,
        precio_unidad REAL
      )
    ''');
    await db.execute('''
      CREATE TABLE product_images (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER,
        image_path TEXT,
        FOREIGN KEY (product_id) REFERENCES productos (id) ON DELETE CASCADE
      )
    ''');
     await db.execute('''
      CREATE TABLE ventas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre_cliente TEXT,
        telefono_cliente TEXT,
        fecha TEXT,
        total REAL,
        estado TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE venta_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        venta_id INTEGER,
        producto_id INTEGER,
        cantidad INTEGER,
        precio_venta REAL,
        es_por_paquete INTEGER,
        verificado INTEGER DEFAULT 0,
        FOREIGN KEY (venta_id) REFERENCES ventas (id) ON DELETE CASCADE,
        FOREIGN KEY (producto_id) REFERENCES productos (id)
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE productos ADD COLUMN unidades_por_paquete INTEGER NOT NULL DEFAULT 1');
      await db.execute('''
        CREATE TABLE ventas (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          nombre_cliente TEXT,
          telefono_cliente TEXT,
          fecha TEXT,
          total REAL
        )
      ''');
      await db.execute('''
        CREATE TABLE venta_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          venta_id INTEGER,
          producto_id INTEGER,
          cantidad INTEGER,
          precio_venta REAL,
          es_por_paquete INTEGER,
          FOREIGN KEY (venta_id) REFERENCES ventas (id) ON DELETE CASCADE,
          FOREIGN KEY (producto_id) REFERENCES productos (id)
        )
      ''');
    }
     if (oldVersion < 5) {
      await db.execute("ALTER TABLE ventas ADD COLUMN estado TEXT DEFAULT 'PENDIENTE'");
      await db.execute("ALTER TABLE venta_items ADD COLUMN verificado INTEGER DEFAULT 0");
    }
  }

  // --- PRODUCTOS ---
  Future<int> insertProduct(Product product) async {
    final db = await database;
    return await db.transaction((txn) async {
      int productId = await txn.insert('productos', product.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.delete('product_images', where: 'product_id = ?', whereArgs: [productId]);
      for (String path in product.fotoPaths) {
        await txn.insert('product_images', {'product_id': productId, 'image_path': path});
      }
      return productId;
    });
  }

  Future<int> updateProduct(Product product) async {
    final db = await database;
     return await db.transaction((txn) async {
      int count = await txn.update('productos', product.toMap(), where: 'id = ?', whereArgs: [product.id]);
      await txn.delete('product_images', where: 'product_id = ?', whereArgs: [product.id]);
      for (String path in product.fotoPaths) {
        await txn.insert('product_images', {'product_id': product.id, 'image_path': path});
      }
      return count;
    });
  }

  Future<int> deleteProduct(int id) async {
    final db = await database;
    return await db.delete('productos', where: 'id = ?', whereArgs: [id]);
  }
  
  Future<void> updateProductStock(int productId, int newStock) async {
    final db = await database;
    await db.update('productos', {'stock': newStock}, where: 'id = ?', whereArgs: [productId]);
  }

  Future<Product?> getProductById(int id) async {
      final db = await database;
      final maps = await db.query('productos', where: 'id = ?', whereArgs: [id]);
      if(maps.isNotEmpty) {
          return Product.fromMap(maps.first);
      }
      return null;
  }

  Future<List<Product>> getProducts() async {
    final db = await database;
    final List<Map<String, dynamic>> productMaps = await db.query('productos');
    List<Product> products = [];
    for (var pMap in productMaps) {
      final List<Map<String, dynamic>> imageMaps = await db.query('product_images', where: 'product_id = ?', whereArgs: [pMap['id']]);
      List<String> imagePaths = imageMaps.map((iMap) => iMap['image_path'] as String).toList();
      products.add(Product.fromMap(pMap).copyWith(fotoPaths: imagePaths));
    }
    return products;
  }
  
  // --- VENTAS ---
  Future<int> insertVenta(Venta venta) async {
    final db = await database;
    return db.transaction((txn) async {
      int ventaId = await txn.insert('ventas', venta.toMap());
      for (var item in venta.items) {
        await txn.insert('venta_items', item.copyWith(ventaId: ventaId).toMap());
      }
      return ventaId;
    });
  }

  Future<List<Venta>> getVentas() async {
    final db = await database;
    final List<Map<String, dynamic>> ventasMaps = await db.query('ventas', orderBy: 'fecha DESC');
    List<Venta> ventas = [];

    for (var vMap in ventasMaps) {
      final List<Map<String, dynamic>> itemsMaps = await db.query('venta_items', where: 'venta_id = ?', whereArgs: [vMap['id']]);
      List<VentaItem> items = [];
      for(var iMap in itemsMaps) {
          Product? product = await getProductById(iMap['producto_id']);
          if(product != null) {
              items.add(VentaItem(
                  id: iMap['id'],
                  ventaId: vMap['id'],
                  producto: product,
                  cantidad: iMap['cantidad'],
                  precioVenta: iMap['precio_venta'],
                  esPorPaquete: iMap['es_por_paquete'] == 1,
                  verificado: iMap['verificado'] == 1,
              ));
          }
      }
      ventas.add(Venta(
        id: vMap['id'],
        nombreCliente: vMap['nombre_cliente'],
        telefonoCliente: vMap['telefono_cliente'],
        fecha: DateTime.parse(vMap['fecha']),
        total: vMap['total'],
        estado: VentaEstado.values.firstWhere((e) => e.toString() == 'VentaEstado.${vMap['estado']}'),
        items: items,
      ));
    }
    return ventas;
  }
  
  Future<void> updateVentaItemVerificado(int itemId, bool verificado) async {
      final db = await database;
      await db.update('venta_items', {'verificado': verificado ? 1 : 0}, where: 'id = ?', whereArgs: [itemId]);
  }

  Future<void> updateVentaEstado(int ventaId, VentaEstado estado) async {
      final db = await database;
      await db.update('ventas', {'estado': estado.toString().split('.').last}, where: 'id = ?', whereArgs: [ventaId]);
  }
}

// Extensión para facilitar la creación de copia de VentaItem
extension VentaItemCopyWith on VentaItem {
  VentaItem copyWith({int? ventaId}) {
    return VentaItem(
      id: id,
      ventaId: ventaId ?? this.ventaId,
      producto: producto,
      cantidad: cantidad,
      precioVenta: precioVenta,
      esPorPaquete: esPorPaquete,
      verificado: verificado
    );
  }
}

// --- PROVIDERS ---

class ProductProvider with ChangeNotifier {
  List<Product> _products = [];
  List<Product> _filteredProducts = [];
  String _searchQuery = '';

  List<Product> get products => _filteredProducts;
  Product? getProductById(int id) {
      try {
          return _products.firstWhere((p) => p.id == id);
      } catch (e) {
          return null;
      }
  }

  ProductProvider() {
    fetchProducts();
  }

  Future<void> fetchProducts() async {
    final dbHelper = DatabaseHelper();
    _products = await dbHelper.getProducts();
    _filterProducts();
    notifyListeners();
  }
  
  void _filterProducts() {
    if (_searchQuery.isEmpty) {
      _filteredProducts = List.from(_products);
    } else {
      final queryLower = _searchQuery.toLowerCase();
      _filteredProducts = _products.where((product) {
        final nombreLower = product.nombre.toLowerCase();
        final marcaLower = product.marca.toLowerCase();
        return nombreLower.contains(queryLower) || marcaLower.contains(queryLower);
      }).toList();
    }
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
  
  Future<void> updateStock(int productId, int newStock) async {
      final dbHelper = DatabaseHelper();
      await dbHelper.updateProductStock(productId, newStock);
      // Actualiza el producto localmente para reflejar el cambio de inmediato
      final productIndex = _products.indexWhere((p) => p.id == productId);
      if(productIndex != -1) {
          _products[productIndex].stock = newStock;
          _filterProducts();
          notifyListeners();
      }
  }

  void search(String query) {
    _searchQuery = query;
    _filterProducts();
    notifyListeners();
  }
}

class VentasProvider with ChangeNotifier {
  List<Venta> _ventas = [];
  List<Venta> get ventas => _ventas;
  final DatabaseHelper _dbHelper = DatabaseHelper();

  VentasProvider() {
    fetchVentas();
  }

  Future<void> fetchVentas() async {
    _ventas = await _dbHelper.getVentas();
    notifyListeners();
  }

  Future<void> addVenta(Venta venta) async {
    await _dbHelper.insertVenta(venta);
    await fetchVentas();
  }
  
  Future<void> updateItemVerificado(int itemId, bool verificado) async {
      await _dbHelper.updateVentaItemVerificado(itemId, verificado);
      await fetchVentas();
  }

  Future<void> completarVenta(Venta venta, ProductProvider productProvider) async {
      for (var item in venta.items) {
          int stockToReduce = item.esPorPaquete 
              ? item.cantidad * item.producto.unidadesPorPaquete 
              : item.cantidad;
          int newStock = item.producto.stock - stockToReduce;
          await productProvider.updateStock(item.producto.id!, newStock);
      }
      await _dbHelper.updateVentaEstado(venta.id!, VentaEstado.COMPLETADA);
      await fetchVentas();
  }
}


void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => ProductProvider()),
        ChangeNotifierProvider(create: (context) => VentasProvider()),
      ],
      child: const MyApp(),
    ),
  );
}


// --- APLICACIÓN PRINCIPAL Y NAVEGACIÓN ---

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Inventario App',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        scaffoldBackgroundColor: Colors.grey[100],
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.indigo.shade800,
          elevation: 4,
          titleTextStyle: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            foregroundColor: Colors.white, 
            backgroundColor: Colors.indigo.shade700,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade400)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade400)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.indigo.shade700, width: 2)),
          filled: true,
          fillColor: Colors.white,
        ),
         bottomNavigationBarTheme: BottomNavigationBarThemeData(
            backgroundColor: Colors.white,
            selectedItemColor: Colors.indigo.shade800,
            unselectedItemColor: Colors.grey.shade600,
            elevation: 10,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  static const List<Widget> _widgetOptions = <Widget>[
    ProductListScreen(),
    SalesListScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: _widgetOptions.elementAt(_selectedIndex),
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.inventory_2_outlined),
            activeIcon: Icon(Icons.inventory_2),
            label: 'Inventario',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.point_of_sale_outlined),
            activeIcon: Icon(Icons.point_of_sale),
            label: 'Ventas',
          ),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
      ),
    );
  }
}

// --- PANTALLAS DE INVENTARIO ---

class ProductListScreen extends StatelessWidget {
  const ProductListScreen({super.key});
  // ... (Esta pantalla y sus métodos auxiliares permanecen casi iguales)
    @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventario'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              onChanged: (value) => Provider.of<ProductProvider>(context, listen: false).search(value),
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
                    child: Text(
                      'No hay productos. ¡Agrega uno!',
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8,0,8,80),
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
                                child: product.fotoPaths.isNotEmpty
                                    ? Image.file(
                                        File(product.fotoPaths.first),
                                        width: 80,
                                        height: 80,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) => _buildErrorIcon(),
                                      )
                                    : _buildErrorIcon(),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      product.nombre,
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Marca: ${product.marca}',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Text('Stock: ${product.stock}', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.blueGrey[700])),
                                        const Spacer(),
                                        Text('Bs. ${product.precioUnidad.toStringAsFixed(2)}/u', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.green[700])),
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
                                      MaterialPageRoute(
                                        builder: (context) => EditProductScreen(product: product),
                                      ),
                                    );
                                  } else if (value == 'delete') {
                                    _showDeleteConfirmationDialog(context, product);
                                  }
                                },
                                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                                  const PopupMenuItem<String>(
                                    value: 'edit',
                                    child: ListTile(leading: Icon(Icons.edit), title: Text('Editar')),
                                  ),
                                  const PopupMenuItem<String>(
                                    value: 'delete',
                                    child: ListTile(leading: Icon(Icons.delete), title: Text('Eliminar')),
                                  ),
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
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddProductScreen()),
          );
        },
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Agregar', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.indigo.shade800,
      ),
    );
  }

  Widget _buildErrorIcon() {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: const Icon(Icons.inventory_2, color: Colors.white, size: 40),
    );
  }
// Pega esto al final de tu clase ProductListScreen
  void _showProductDetailModal(BuildContext context, Product product) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
             int _currentCarouselIndex = 0;
            return AlertDialog(
              contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              title: Text(product.nombre, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (product.fotoPaths.isNotEmpty)
                      Column(
                        children: [
                          CarouselSlider(
                            options: CarouselOptions(
                              height: 250,
                              viewportFraction: 1.0,
                              enlargeCenterPage: false,
                              onPageChanged: (index, reason) {
                                setState(() {
                                  _currentCarouselIndex = index;
                                });
                              },
                            ),
                            items: product.fotoPaths.map((path) {
                              return Builder(
                                builder: (BuildContext context) {
                                  return Container(
                                    width: MediaQuery.of(context).size.width,
                                    margin: const EdgeInsets.symmetric(horizontal: 2.0),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12.0),
                                      child: Image.file(
                                        File(path),
                                        fit: BoxFit.cover,
                                        errorBuilder: (c, o, s) => const Icon(Icons.error, size: 50, color: Colors.red),
                                      ),
                                    ),
                                  );
                                },
                              );
                            }).toList(),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: product.fotoPaths.asMap().entries.map((entry) {
                              return Container(
                                  width: _currentCarouselIndex == entry.key ? 10.0 : 8.0,
                                  height: _currentCarouselIndex == entry.key ? 10.0 : 8.0,
                                  margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                                  decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.indigo.withOpacity(_currentCarouselIndex == entry.key ? 0.9 : 0.4)),
                                );
                            }).toList(),
                          ),
                        ],
                      )
                    else
                      Container(
                        width: double.infinity,
                        height: 250,
                        decoration: BoxDecoration(
                           color: Colors.grey.shade300,
                           borderRadius: BorderRadius.circular(12.0),
                        ),
                        child: const Icon(Icons.camera_alt, color: Colors.white, size: 80),
                      ),
                    const SizedBox(height: 20),
                    Text('Marca: ${product.marca}', style: TextStyle(fontSize: 18, color: Colors.grey.shade700)),
                    const SizedBox(height: 10),
                    Text('Ubicación: ${product.ubicacion}', style: TextStyle(fontSize: 18, color: Colors.grey.shade700)),
                    const SizedBox(height: 10),
                     Text('Unidades por Paquete: ${product.unidadesPorPaquete}', style: TextStyle(fontSize: 18, color: Colors.grey.shade700)),
                    const SizedBox(height: 10),
                    Text('Stock disponible: ${product.stock} unidades', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Text('Precio por Paquete: Bs. ${product.precioPaquete.toStringAsFixed(2)}', style: TextStyle(fontSize: 18, color: Colors.green[800])),
                    const SizedBox(height: 10),
                    Text('Precio por Unidad: Bs. ${product.precioUnidad.toStringAsFixed(2)}', style: TextStyle(fontSize: 18, color: Colors.green[800])),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cerrar', style: TextStyle(fontSize: 16)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showDeleteConfirmationDialog(BuildContext context, Product product) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirmar Eliminación'),
          content: Text('¿Estás seguro de que quieres eliminar "${product.nombre}"?'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () {
                Provider.of<ProductProvider>(context, listen: false).deleteProduct(product.id!);
                Navigator.of(context).pop();
                 ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('"${product.nombre}" eliminado.'), backgroundColor: Colors.red),
                );
              },
              child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }
}


// --- FORMULARIOS DE PRODUCTO ---

abstract class ProductFormScreen extends StatefulWidget {
    const ProductFormScreen({super.key});
}

abstract class ProductFormScreenState<T extends ProductFormScreen> extends State<T> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _marcaController = TextEditingController();
  final _ubicacionController = TextEditingController();
  final _unidadesController = TextEditingController();
  final _stockController = TextEditingController();
  final _precioPaqueteController = TextEditingController();
  final _precioUnidadController = TextEditingController();
  final List<XFile> _imageFiles = [];
  List<String> _existingImagePaths = [];

  @override
  void dispose() {
    _nombreController.dispose();
    _marcaController.dispose();
    _ubicacionController.dispose();
    _unidadesController.dispose();
    _stockController.dispose();
    _precioPaqueteController.dispose();
    _precioUnidadController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    try {
      final XFile? image = await picker.pickImage(source: ImageSource.camera, imageQuality: 70);
       if (image != null) setState(() => _imageFiles.add(image));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al tomar la foto: $e')));
    }
  }

  void _removeNewImage(int index) => setState(() => _imageFiles.removeAt(index));
  void _removeExistingImage(int index) => setState(() => _existingImagePaths.removeAt(index));

  Future<void> saveProduct();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(this is _AddProductScreenState ? 'Agregar Producto' : 'Editar Producto'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(controller: _nombreController, decoration: const InputDecoration(labelText: 'Nombre del Producto'), validator: (v) => (v == null || v.isEmpty) ? 'Ingresa un nombre' : null),
              const SizedBox(height: 16),
              TextFormField(controller: _marcaController, decoration: const InputDecoration(labelText: 'Marca'), validator: (v) => (v == null || v.isEmpty) ? 'Ingresa una marca' : null),
              const SizedBox(height: 16),
              TextFormField(controller: _ubicacionController, decoration: const InputDecoration(labelText: 'Ubicación (Piso/Estante)'), validator: (v) => (v == null || v.isEmpty) ? 'Ingresa una ubicación' : null),
              const SizedBox(height: 16),
              TextFormField(controller: _unidadesController, decoration: const InputDecoration(labelText: 'Unidades por Paquete'), keyboardType: TextInputType.number, validator: (v) {
                  if (v == null || v.isEmpty) return 'Ingresa las unidades';
                  if (int.tryParse(v) == null || int.parse(v) < 1) return 'Debe ser un número mayor a 0';
                  return null;
              }),
              const SizedBox(height: 16),
              TextFormField(controller: _stockController, decoration: const InputDecoration(labelText: 'Stock (Unidades)'), keyboardType: TextInputType.number, validator: (v) {
                  if (v == null || v.isEmpty) return 'Ingresa el stock';
                  if (int.tryParse(v) == null) return 'Ingresa un número válido';
                  return null;
              }),
              const SizedBox(height: 16),
              TextFormField(controller: _precioPaqueteController, decoration: const InputDecoration(labelText: 'Precio por Paquete (Bs.)'), keyboardType: const TextInputType.numberWithOptions(decimal: true), validator: (v) {
                  if (v == null || v.isEmpty) return 'Ingresa un precio';
                  if (double.tryParse(v) == null) return 'Ingresa un número válido';
                  return null;
              }),
              const SizedBox(height: 16),
              TextFormField(controller: _precioUnidadController, decoration: const InputDecoration(labelText: 'Precio por Unidad (Bs.)'), keyboardType: const TextInputType.numberWithOptions(decimal: true), validator: (v) {
                  if (v == null || v.isEmpty) return 'Ingresa un precio';
                  if (double.tryParse(v) == null) return 'Ingresa un número válido';
                  return null;
              }),
              const SizedBox(height: 32),
              const Text("Fotos del Producto", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Container(
                height: 120,
                decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(12)),
                child: (_imageFiles.isEmpty && _existingImagePaths.isEmpty) 
                ? const Center(child: Text('Añade una o más fotos.'))
                : ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.all(8), children: [
                    ..._existingImagePaths.asMap().entries.map((e) => _buildImageThumbnail(File(e.value), () => _removeExistingImage(e.key))),
                    ..._imageFiles.asMap().entries.map((e) => _buildImageThumbnail(File(e.value.path), () => _removeNewImage(e.key))),
                  ]),
              ),
               const SizedBox(height: 16),
              ElevatedButton.icon(onPressed: _pickImage, icon: const Icon(Icons.camera_alt, color: Colors.white), label: const Text('Tomar Foto', style: TextStyle(color: Colors.white)), style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, padding: const EdgeInsets.symmetric(vertical: 20))),
              const SizedBox(height: 32),
              ElevatedButton(onPressed: saveProduct, child: Text(this is _AddProductScreenState ? 'Guardar Producto' : 'Guardar Cambios')),
            ],
          ),
        ),
      ),
    );
  }

   Widget _buildImageThumbnail(File imageFile, VoidCallback onRemove) {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: Stack(children: [
          ClipRRect(borderRadius: BorderRadius.circular(8.0), child: Image.file(imageFile, width: 100, height: 100, fit: BoxFit.cover, errorBuilder: (c, o, s) => Container(width: 100, height: 100, color: Colors.grey.shade300, child: const Icon(Icons.broken_image, color: Colors.white)))),
          Positioned(top: 2, right: 2, child: GestureDetector(onTap: onRemove, child: Container(padding: const EdgeInsets.all(2), decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle), child: const Icon(Icons.close, color: Colors.white, size: 16)))),
      ]),
    );
  }
}

class AddProductScreen extends ProductFormScreen {
  const AddProductScreen({super.key});
  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends ProductFormScreenState<AddProductScreen> {
  @override
  Future<void> saveProduct() async {
    if (!super._formKey.currentState!.validate()) return;
    if (super._imageFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Por favor, toma al menos una foto del producto.')));
      return;
    }
    
    final List<String> savedImagePaths = [];
    final Directory appDir = await getApplicationDocumentsDirectory();
    for (var file in super._imageFiles) {
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${p.basename(file.path)}';
      final savedPath = p.join(appDir.path, fileName);
      await File(file.path).copy(savedPath);
      savedImagePaths.add(savedPath);
    }
    
    final newProduct = Product(
      nombre: super._nombreController.text,
      marca: super._marcaController.text,
      ubicacion: super._ubicacionController.text,
      unidadesPorPaquete: int.parse(super._unidadesController.text),
      stock: int.parse(super._stockController.text),
      precioPaquete: double.parse(super._precioPaqueteController.text),
      precioUnidad: double.parse(super._precioUnidadController.text),
      fotoPaths: savedImagePaths,
    );
    
    if (!mounted) return;
    await Provider.of<ProductProvider>(context, listen: false).addProduct(newProduct);
    Navigator.pop(context);
  }
}

class EditProductScreen extends ProductFormScreen {
  final Product product;
  const EditProductScreen({super.key, required this.product});
  @override
  State<EditProductScreen> createState() => _EditProductScreenState();
}

class _EditProductScreenState extends ProductFormScreenState<EditProductScreen> {
  @override
  void initState() {
    super.initState();
    super._nombreController.text = widget.product.nombre;
    super._marcaController.text = widget.product.marca;
    super._ubicacionController.text = widget.product.ubicacion;
    super._unidadesController.text = widget.product.unidadesPorPaquete.toString();
    super._stockController.text = widget.product.stock.toString();
    super._precioPaqueteController.text = widget.product.precioPaquete.toString();
    super._precioUnidadController.text = widget.product.precioUnidad.toString();
    super._existingImagePaths = List.from(widget.product.fotoPaths);
  }
  
  @override
  Future<void> saveProduct() async {
    if (!super._formKey.currentState!.validate()) return;
    if (super._imageFiles.isEmpty && super._existingImagePaths.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('El producto debe tener al menos una foto.')));
      return;
    }
    
    final finalImagePaths = List<String>.from(super._existingImagePaths);
    final Directory appDir = await getApplicationDocumentsDirectory();
    for (var file in super._imageFiles) {
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${p.basename(file.path)}';
      final savedPath = p.join(appDir.path, fileName);
      await File(file.path).copy(savedPath);
      finalImagePaths.add(savedPath);
    }
    
    final updatedProduct = Product(
      id: widget.product.id,
      nombre: super._nombreController.text,
      marca: super._marcaController.text,
      ubicacion: super._ubicacionController.text,
      unidadesPorPaquete: int.parse(super._unidadesController.text),
      stock: int.parse(super._stockController.text),
      precioPaquete: double.parse(super._precioPaqueteController.text),
      precioUnidad: double.parse(super._precioUnidadController.text),
      fotoPaths: finalImagePaths,
    );
    
    if (!mounted) return;
    await Provider.of<ProductProvider>(context, listen: false).updateProduct(updatedProduct);
    Navigator.pop(context);
  }
}

// --- PANTALLAS DE VENTAS ---

class SalesListScreen extends StatelessWidget {
  const SalesListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Historial de Ventas')),
      body: Consumer<VentasProvider>(
        builder: (context, provider, child) {
          if (provider.ventas.isEmpty) {
            return const Center(child: Text('No hay ventas registradas.', style: TextStyle(fontSize: 18, color: Colors.grey)));
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 80),
            itemCount: provider.ventas.length,
            itemBuilder: (context, index) {
              final venta = provider.ventas[index];
              final isPending = venta.estado == VentaEstado.PENDIENTE;
              return Card(
                color: isPending ? Colors.amber[50] : Colors.white,
                child: ListTile(
                  title: Text(venta.nombreCliente, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('${DateFormat('dd/MM/yyyy HH:mm').format(venta.fecha)}\nTotal: Bs. ${venta.total.toStringAsFixed(2)}'),
                  isThreeLine: true,
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isPending ? Colors.orange : Colors.green,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      isPending ? 'PENDIENTE' : 'COMPLETADA',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                  onTap: () {
                     Navigator.push(context, MaterialPageRoute(builder: (_) => SaleDetailScreen(venta: venta)));
                  },
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateSaleScreen())),
        label: const Text('Nueva Venta', style: TextStyle(color: Colors.white)),
        icon: const Icon(Icons.add, color: Colors.white),
        backgroundColor: Colors.indigo.shade800,
      ),
    );
  }
}

class CreateSaleScreen extends StatefulWidget {
  const CreateSaleScreen({super.key});
  @override
  State<CreateSaleScreen> createState() => _CreateSaleScreenState();
}

class _CreateSaleScreenState extends State<CreateSaleScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreClienteController = TextEditingController();
  final _telefonoClienteController = TextEditingController();
  final List<VentaItem> _cart = [];
  double _total = 0.0;

  void _addToCart(Product product, int quantity, bool isPackage) {
    final price = isPackage ? product.precioPaquete : product.precioUnidad;
    final stockNeeded = isPackage ? quantity * product.unidadesPorPaquete : quantity;

    if (stockNeeded > product.stock) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Stock insuficiente. Disponible: ${product.stock} unidades.'), backgroundColor: Colors.red));
      return;
    }

    setState(() {
      _cart.add(VentaItem(ventaId: 0, producto: product, cantidad: quantity, precioVenta: price, esPorPaquete: isPackage));
      _calculateTotal();
    });
  }

  void _removeFromCart(int index) {
    setState(() {
      _cart.removeAt(index);
      _calculateTotal();
    });
  }

  void _calculateTotal() {
    _total = _cart.fold(0.0, (sum, item) => sum + (item.cantidad * item.precioVenta));
  }
  
  void _showAddProductDialog() {
    final productProvider = Provider.of<ProductProvider>(context, listen: false);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Seleccionar Producto'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              itemCount: productProvider.products.length,
              itemBuilder: (context, index) {
                final product = productProvider.products[index];
                return ListTile(
                  title: Text(product.nombre),
                  subtitle: Text('Stock: ${product.stock}'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _showQuantityDialog(product);
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }
  
  void _showQuantityDialog(Product product) {
    final quantityController = TextEditingController();
    bool isPackage = false;
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(product.nombre),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: quantityController, decoration: const InputDecoration(labelText: 'Cantidad'), keyboardType: TextInputType.number),
                  SwitchListTile(
                    title: const Text('Vender por paquete'),
                    value: isPackage,
                    onChanged: (val) => setState(() => isPackage = val),
                    subtitle: Text(isPackage ? '${product.unidadesPorPaquete} unidades' : 'Venta por unidad'),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
                ElevatedButton(
                  onPressed: () {
                    final quantity = int.tryParse(quantityController.text) ?? 0;
                    if (quantity > 0) {
                      _addToCart(product, quantity, isPackage);
                      Navigator.of(context).pop();
                    }
                  },
                  child: const Text('Añadir'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _saveVenta() async {
      if(!_formKey.currentState!.validate()) return;
      if(_cart.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Añade al menos un producto a la venta.')));
          return;
      }
      final newVenta = Venta(
          nombreCliente: _nombreClienteController.text,
          telefonoCliente: _telefonoClienteController.text,
          fecha: DateTime.now(),
          total: _total,
          items: _cart,
      );
      await Provider.of<VentasProvider>(context, listen: false).addVenta(newVenta);
      if(!mounted) return;
      Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crear Venta')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Datos del Cliente', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextFormField(controller: _nombreClienteController, decoration: const InputDecoration(labelText: 'Nombre del Cliente'), validator: (v) => v!.isEmpty ? 'Campo requerido' : null),
              const SizedBox(height: 16),
              TextFormField(controller: _telefonoClienteController, decoration: const InputDecoration(labelText: 'Teléfono (Opcional)'), keyboardType: TextInputType.phone),
              const Divider(height: 40),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Productos en la Lista', style: Theme.of(context).textTheme.titleLarge),
                  IconButton(icon: const Icon(Icons.add_shopping_cart, color: Colors.indigo), onPressed: _showAddProductDialog),
                ],
              ),
              const SizedBox(height: 8),
              _cart.isEmpty
                  ? const Text('Aún no hay productos.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey))
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _cart.length,
                      itemBuilder: (context, index) {
                        final item = _cart[index];
                        return Card(
                          child: ListTile(
                            title: Text(item.producto.nombre),
                            subtitle: Text('${item.cantidad} x ${item.esPorPaquete ? "Paquete" : "Unidad"} @ Bs. ${item.precioVenta.toStringAsFixed(2)}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('Bs. ${(item.cantidad * item.precioVenta).toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _removeFromCart(index)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
              const Divider(height: 40),
              Text('Total: Bs. ${_total.toStringAsFixed(2)}', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 30),
              ElevatedButton(onPressed: _saveVenta, child: const Text('Guardar Venta Pendiente')),
            ],
          ),
        ),
      ),
    );
  }
}

class SaleDetailScreen extends StatefulWidget {
  final Venta venta;
  const SaleDetailScreen({super.key, required this.venta});
  @override
  State<SaleDetailScreen> createState() => _SaleDetailScreenState();
}

class _SaleDetailScreenState extends State<SaleDetailScreen> {
  late List<VentaItem> _items;
  bool _isCompleted = false;

  @override
  void initState() {
    super.initState();
    _items = widget.venta.items;
    _isCompleted = widget.venta.estado == VentaEstado.COMPLETADA;
  }

  bool get _allChecked => _items.every((item) => item.verificado);

  Future<void> _completeSale() async {
    final ventasProvider = Provider.of<VentasProvider>(context, listen: false);
    final productProvider = Provider.of<ProductProvider>(context, listen: false);
    await ventasProvider.completarVenta(widget.venta, productProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Venta completada y stock actualizado.'), backgroundColor: Colors.green));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Detalle Venta #${widget.venta.id}')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cliente: ${widget.venta.nombreCliente}', style: Theme.of(context).textTheme.titleLarge),
            if(widget.venta.telefonoCliente.isNotEmpty)
              Text('Teléfono: ${widget.venta.telefonoCliente}', style: Theme.of(context).textTheme.titleMedium),
            Text('Fecha: ${DateFormat('dd/MM/yyyy HH:mm').format(widget.venta.fecha)}', style: Theme.of(context).textTheme.titleMedium),
             const Divider(height: 30),
            Text('Lista de Verificación', style: Theme.of(context).textTheme.titleLarge),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final item = _items[index];
                return CheckboxListTile(
                  title: Text(item.producto.nombre),
                  subtitle: Text('${item.cantidad} x ${item.esPorPaquete ? "Paquete" : "Unidad"}'),
                  value: item.verificado,
                  onChanged: _isCompleted ? null : (bool? value) {
                    setState(() {
                      item.verificado = value ?? false;
                    });
                     Provider.of<VentasProvider>(context, listen: false).updateItemVerificado(item.id!, item.verificado);
                  },
                  activeColor: Colors.indigo,
                  controlAffinity: ListTileControlAffinity.leading,
                );
              },
            ),
             const Divider(height: 30),
             Text('Total: Bs. ${widget.venta.total.toStringAsFixed(2)}', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
             const SizedBox(height: 30),
             if(!_isCompleted)
                ElevatedButton(
                    onPressed: _allChecked ? _completeSale : null,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    child: const Text('Completar Venta'),
                ),
          ],
        ),
      ),
    );
  }
}
