import 'spanish_catalog.dart';
import 'shopping_market_translations.dart';

/// Reviewed overrides take precedence over the generated Latin American
/// Spanish catalog. Source copy is retained only for an unknown phrase.
const spanishUiTranslations = <String, String>{
  ...spanishCatalog,
  ...shoppingMarketSpanish,
  'Paste from clipboard': 'Pegar desde el portapapeles',
  'Retry duplicate check': 'Reintentar la comprobación de duplicados',
  'Duplicate check required': 'Se requiere comprobar duplicados',
  'There are no products to import. Include the header row and product list.':
      'No hay productos para importar. Incluye la fila de encabezados y la lista de productos.',
  'The clipboard is empty. Copy an Excel table or product list first.':
      'El portapapeles está vacío. Primero copia una tabla de Excel o una lista de productos.',
  'Could not read the clipboard. Select the list field and use Ctrl+V or Paste.':
      'No se pudo leer el portapapeles. Selecciona el campo de la lista y usa Ctrl+V o Pegar.',
  'Could not read the selected file. Select it again, or copy the table and paste it into the list field.':
      'No se pudo leer el archivo seleccionado. Selecciónalo de nuevo o copia la tabla y pégala en el campo de la lista.',
  'The list was read, but the server could not finish checking duplicates. Check your connection and run the preview again.':
      'Se leyó la lista, pero el servidor no pudo terminar de comprobar los duplicados. Revisa tu conexión y vuelve a ejecutar la vista previa.',
  'This CSV uses the Korean CP949 encoding. Save it as CSV UTF-8 in Excel or select an XLSX file. You can also copy and paste the table with its header row.':
      'Este CSV usa la codificación coreana CP949. Guárdalo como CSV UTF-8 en Excel o selecciona un archivo XLSX. También puedes copiar y pegar la tabla con su fila de encabezados.',
  'The file or pasted content is too large. Split it into parts of 2 MB or less.':
      'El archivo o el contenido pegado es demasiado grande. Divídelo en partes de 2 MB o menos.',
  'You can import up to 2,000 products at a time. Split the list into smaller parts.':
      'Puedes importar hasta 2,000 productos a la vez. Divide la lista en partes más pequeñas.',
  'Check the product title and affiliate link headers in the first row. Use each column header only once.':
      'Revisa los encabezados de nombre del producto y enlace de afiliado en la primera fila. Usa cada encabezado de columna solo una vez.',
  'The CSV has unmatched quotation marks. Save it again as CSV UTF-8 in Excel, or copy and paste the table.':
      'El CSV tiene comillas sin cerrar. Vuelve a guardarlo como CSV UTF-8 en Excel o copia y pega la tabla.',
  'The file or table could not be read. Use an XLSX or CSV UTF-8 file, or paste the table including its header row.':
      'No se pudo leer el archivo o la tabla. Usa un archivo XLSX o CSV UTF-8, o pega la tabla con su fila de encabezados.',
  'If the ingredient is blank, the product title is used. You can copy and paste an Excel table starting with its header row.':
      'Si el ingrediente está vacío, se usa el nombre del producto. Puedes copiar y pegar una tabla de Excel desde la fila de encabezados.',
  'Recipe Scout': 'Explorador de recetas',
  'Home': 'Inicio',
  'More': 'Más',
  'My recipes': 'Mis recetas',
  'Shopping': 'Compras',
  'Account': 'Cuenta',
  'Sign in': 'Iniciar sesión',
  'Sign out': 'Cerrar sesión',
  'Save': 'Guardar',
  'Cancel': 'Cancelar',
  'Close': 'Cerrar',
  'Back': 'Volver',
  'Next': 'Siguiente',
  'Previous': 'Anterior',
  'Continue': 'Continuar',
  'Done': 'Listo',
  'Retry': 'Reintentar',
  'Reload': 'Actualizar',
  'Search': 'Buscar',
  'Clear': 'Limpiar',
  'Edit': 'Editar',
  'Delete': 'Eliminar',
  'Restore': 'Restaurar',
  'Archive': 'Archivar',
  'Confirm': 'Confirmar',
  'Add': 'Agregar',
  'TXT, CSV, TSV or XLSX: up to 2 MB and 2,000 rows. Only the first Excel worksheet is read.':
      'TXT, CSV, TSV o XLSX: hasta 2 MB y 2.000 filas. Solo se lee la primera hoja de Excel.',
  'If creating a CSV is difficult, paste one line at a time below. Use ingredient | product name | affiliate link, or product name | affiliate link.':
      'Si crear un CSV es difícil, pega una línea a la vez abajo. Usa ingrediente | nombre del producto | enlace de afiliado, o nombre del producto | enlace de afiliado.',
  'Check the pasted text. On each line, separate ingredient, product name and affiliate link with |.':
      'Revisa el texto pegado. En cada línea, separa el ingrediente, el producto y el enlace de afiliado con |.',
  'Preview quick paste': 'Vista previa del pegado rápido',
  'This is a similar product. Check the ingredient type, cut and package size before buying.':
      'Este es un producto similar. Revisa el tipo de ingrediente, el corte y el tamaño del envase antes de comprar.',
  'A Coupang affiliate product is available. Check the package size and choose it.':
      'Hay un producto afiliado de Coupang disponible. Revisa el tamaño del envase y elígelo.',
  '1 Coupang affiliate product is available. Compare package sizes and choose one.':
      'Hay 1 producto afiliado de Coupang disponible. Compara los tamaños de los envases y elige uno.',
  '{1} Coupang affiliate products are available. Compare package sizes and choose one.':
      'Hay {1} productos afiliados de Coupang disponibles. Compara los tamaños de los envases y elige uno.',
  'Choose from 1 product': 'Elige entre 1 producto',
  'Choose from {1} products': 'Elige entre {1} productos',
  'Review and choose product': 'Revisar y elegir producto',
  'Remove': 'Quitar',
  'Select': 'Seleccionar',
  'Selected': 'Seleccionado',
  'All': 'Todo',
  'None': 'Ninguno',
  'Loading': 'Cargando',
  'Saving': 'Guardando',
  'Saved': 'Guardado',
  'Error': 'Error',
  'Required': 'Obligatorio',
  'Optional': 'Opcional',
  'Details': 'Detalles',
  'History': 'Historial',
  'Settings': 'Configuración',
  'Help': 'Ayuda',
  'Discover what to cook today.': 'Descubre qué cocinar hoy.',
  'Discover your next meal': 'Descubre tu próxima comida',
  'Save dishes you love to your recipes.':
      'Guarda los platos que te gustan en tus recetas.',
  'From video to table': 'Del video a la mesa',
  'Tasty discoveries,\nyour own recipes.':
      'Descubrimientos deliciosos,\ntus propias recetas.',
  'Find a cooking video you love\nand turn its AI draft into your recipe note.':
      'Encuentra un video de cocina\ny convierte su borrador de IA en tu receta.',
  'Find video recipes': 'Buscar recetas en video',
  'Search by ingredients': 'Buscar por ingredientes',
  'Guided tutorials': 'Tutoriales guiados',
  'Find your first recipe?': '¿Buscamos tu primera receta?',
  'Search by dish name or start with a video.':
      'Busca por nombre del plato o comienza con un video.',
  'Could not load recipes': 'No se pudieron cargar las recetas',
  'Check your connection and try again.':
      'Revisa tu conexión e inténtalo de nuevo.',
  'Try again': 'Intentar de nuevo',
  'Loading recipes': 'Cargando recetas',
  'Home cook': 'Cocina en casa',
  'Kitchen professional': 'Profesional de cocina',
  'Food supplier': 'Proveedor de alimentos',
  'Find recipes': 'Buscar recetas',
  'Recipe library': 'Biblioteca de recetas',
  'Requests': 'Solicitudes',
  'Purchasing': 'Compras profesionales',
  'Suppliers': 'Proveedores',
  'Recipe development': 'Desarrollo de recetas',
  'Business profile': 'Perfil del negocio',
  'Products': 'Productos',
  'Trade terms': 'Condiciones comerciales',
  'Shopping menu': 'Menú de compras',
  'Prepare shopping list': 'Preparar lista de compras',
  'Confirm purchase list': 'Confirmar lista de compra',
  'Purchase list confirmed': 'Lista de compra confirmada',
  'Ingredients to buy': 'Ingredientes por comprar',
  'Review shopping lists': 'Revisar listas de compras',
  'Shopping tools': 'Herramientas de compra',
  'Purchase preparation': 'Preparación de compra',
  'Check amounts → choose a Coupang product → buy':
      'Revisa las cantidades → elige un producto de Coupang → compra',
  'Amounts come from your recipe and servings. Choose the pack and quantity at Coupang.':
      'Las cantidades provienen de tu receta y porciones. Elige la presentación y cantidad en Coupang.',
  'Calculate amounts for servings': 'Calcular cantidades para las porciones',
  'Enter the recipe servings and servings to cook. Only recipe-derived amounts are recalculated; quantities you edited stay unchanged.':
      'Indica las porciones de la receta y las que vas a preparar. Solo se recalculan las cantidades tomadas de la receta; las cantidades que editaste no cambian.',
  'Recipe servings': 'Porciones de la receta',
  'Servings to cook': 'Porciones a preparar',
  'Calculate amounts': 'Calcular cantidades',
  'Enter recipe servings and servings to cook between 0.1 and 1,000.':
      'Ingresa las porciones de la receta y las que vas a preparar entre 0,1 y 1.000.',
  'Could not calculate quantities for the servings. Check the quantities directly.':
      'No se pudieron calcular las cantidades para las porciones. Revisa las cantidades directamente.',
  'Purchase requests': 'Solicitudes de compra',
  'Item purchases': 'Compras de artículos',
  'Purchase item': 'Artículo de compra',
  'Purchase amount': 'Cantidad de compra',
  'Purchase unit': 'Unidad de compra',
  'Purchase history': 'Historial de compras',
  'Purchase records': 'Registros de compra',
  'Add to shopping list': 'Agregar a la lista de compras',
  'Add ingredients': 'Agregar ingredientes',
  'Required quantity': 'Cantidad necesaria',
  'Unit': 'Unidad',
  'Size or brand (optional)': 'Tamaño o marca (opcional)',
  'Find Coupang products': 'Buscar productos en Coupang',
  'Check sizes on Coupang': 'Revisar tamaños en Coupang',
  'Google Shopping': 'Google Shopping',
  'Open Google Shopping': 'Abrir Google Shopping',
  'Search Coupang': 'Buscar en Coupang',
  'Buy on Coupang': 'Comprar en Coupang',
  'Ingredients': 'Ingredientes',
  'Ingredient': 'Ingrediente',
  'Cooking instructions': 'Instrucciones de cocina',
  'Cooking steps': 'Pasos de preparación',
  'Notes': 'Notas',
  'Tips': 'Consejos',
  'Servings': 'Porciones',
  'Preparation time': 'Tiempo de preparación',
  'Cooking time': 'Tiempo de cocción',
  'Recipe title': 'Título de la receta',
  'Create recipe': 'Crear receta',
  'Import recipe': 'Importar receta',
  'Saved recipes': 'Recetas guardadas',
  'Recipe details': 'Detalles de la receta',
  'Recipe source': 'Fuente de la receta',
  'Original': 'Original',
  'Translate': 'Traducir',
  'Show original': 'Ver original',
  'Use AI': 'Usar IA',
  'AI suggestions': 'Sugerencias de IA',
  'AI categories and matching ingredients':
      'Categorías de IA e ingredientes coincidentes',
  'Search results': 'Resultados de búsqueda',
  'No results.': 'No hay resultados.',
  'No matching records.': 'No hay registros coincidentes.',
  'No saved plans.': 'No hay planes guardados.',
  'No meals planned yet': 'Aún no hay comidas planificadas',
  'Could not complete. Refresh and check again.':
      'No se pudo completar. Actualiza e inténtalo de nuevo.',
  'Could not load records. Check access and connection, then retry.':
      'No se pudieron cargar los registros. Revisa el acceso y la conexión e inténtalo de nuevo.',
  'Could not load the purchase list.': 'No se pudo cargar la lista de compra.',
  'Could not save your draft. Check and retry.':
      'No se pudo guardar tu borrador. Revisa e inténtalo de nuevo.',
  'Login': 'Iniciar sesión',
  'Email': 'Correo electrónico',
  'Password': 'Contraseña',
  'Forgot password?': '¿Olvidaste tu contraseña?',
  'Create account': 'Crear cuenta',
  'Sign up': 'Registrarse',
  'Continue with Google': 'Continuar con Google',
  'Continue with Kakao': 'Continuar con Kakao',
  'Two-step verification': 'Verificación en dos pasos',
  'Personal space': 'Espacio personal',
  'Workspace & security': 'Espacio de trabajo y seguridad',
  'Service administration': 'Administración del servicio',
  'Help & information': 'Ayuda e información',
  'Your account, your way': 'Tu cuenta, a tu manera',
  'Manage your workspace, security and service preferences.':
      'Administra tu espacio de trabajo, seguridad y preferencias del servicio.',
  'Supplier name': 'Nombre del proveedor',
  'Contact details': 'Datos de contacto',
  'Product details': 'Detalles del producto',
  'Product name': 'Nombre del producto',
  'Product list': 'Lista de productos',
  'Availability': 'Disponibilidad',
  'Category': 'Categoría',
  'Subcategory': 'Subcategoría',
  'Price': 'Precio',
  'Stock': 'Inventario',
  'Inventory': 'Inventario',
  'Stock management note': 'Nota de gestión de inventario',
  'Receiving & returns': 'Recepción y devoluciones',
  'Delivery date & stock': 'Fecha de entrega e inventario',
  'Delivery & order terms': 'Condiciones de entrega y pedido',
  'Business name': 'Nombre del negocio',
  'Business region': 'Región del negocio',
  'Delivery regions': 'Regiones de entrega',
  'Manage': 'Gestionar',
  'Administration tasks': 'Tareas de administración',
  'Operations alerts & checks': 'Alertas y revisiones operativas',
  'Member management': 'Gestión de miembros',
  'Members & invitations': 'Miembros e invitaciones',
  'Status': 'Estado',
  'Updated': 'Actualizado',
  'Created': 'Creado',
  'Today': 'Hoy',
  'Yesterday': 'Ayer',
  'Day': 'Día',
  'Week': 'Semana',
  'Month': 'Mes',
  'ea': 'ud.',
  '{0}% · {1} attempts / hour': '{0}% · {1} intentos / hora',
  '{0}% · {1} requests / hour': '{0}% · {1} solicitudes / hora',
  'P95 {0} seconds': 'P95 {0} segundos',
  '{0}% (configured DB budget)':
      '{0}% (presupuesto de capacidad de BD configurado)',
  '{0}% · {1} DB connections': '{0}% · {1} conexiones a la BD',
  'Edit the product details so the Coupang product and package size can be checked first.':
      'Edita los datos del producto para poder comprobar primero el producto de Coupang y el tamaño del paquete.',
  'Verify Coupang product and image':
      'Verificar el producto y la imagen de Coupang',
  'Check the product name and photo to confirm the item and package size. The selected Coupang photo will be saved and published in Shopping.':
      'Comprueba el nombre y la foto para confirmar el producto y el tamaño del paquete. La foto de Coupang seleccionada se guardará y se publicará en Compras.',
  'Publish to Shopping?': '¿Publicar en Compras?',
  'Confirm to save the Coupang product photo and publish it in the app shopping list. The issued affiliate link stays unchanged, and the offer will need review again in 30 days.':
      'Confirma para guardar la foto del producto de Coupang y publicarla en la lista de compras de la aplicación. El enlace de afiliado emitido no cambia y habrá que revisar la oferta de nuevo en 30 días.',
  'Confirm and publish': 'Confirmar y publicar',
  'Coupang search result and photo verified by admin':
      'Resultado de búsqueda y foto de Coupang verificados por el administrador',
  'Coupang product photo saved and confirmed visible in app Shopping':
      'Foto del producto de Coupang guardada y visible en Compras de la aplicación',
  'The product and photo were saved and published, but could not be confirmed in app Shopping yet. Check publication status and connectivity.':
      'El producto y la foto se guardaron y publicaron, pero aún no se pudo confirmar su aparición en Compras de la aplicación. Revisa el estado de publicación y la conexión.',
  'Coupang product photo saved and confirmed visible in app Shopping.':
      'Foto del producto de Coupang guardada y visible en Compras de la aplicación.',
  'Saved successfully, but Shopping visibility could not be confirmed.':
      'Se guardó correctamente, pero no se pudo confirmar su visibilidad en Compras.',
  'Coupang Partners API setup is required.':
      'Es necesario configurar la API de Coupang Partners.',
  'The Coupang lookup limit was reached. Please try again later.':
      'Se alcanzó el límite de consultas de Coupang. Inténtalo de nuevo más tarde.',
  'No Coupang product with a photo was found. Nothing was published.':
      'No se encontró ningún producto de Coupang con foto. No se publicó nada.',
  'Could not verify the Coupang product. Check your connection and try again.':
      'No se pudo verificar el producto de Coupang. Revisa la conexión e inténtalo de nuevo.',
  'Could not save. Check administrator access and product details, then try again.':
      'No se pudo guardar. Revisa el acceso de administrador y los datos del producto, e inténtalo de nuevo.',
  'Verify Coupang product and publish to Shopping':
      'Verificar el producto de Coupang y publicar en Compras',
  'Coupang product photo': 'Foto del producto de Coupang',
};
