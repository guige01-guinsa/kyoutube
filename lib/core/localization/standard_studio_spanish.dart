// Interface translations only; the production profile remains Korean-only.
const standardStudioSpanish = <String, String>{
  'Immediate execution requested. Progress updates automatically.':
      'Se solicitó la ejecución inmediata. El progreso se actualiza automáticamente.',
  'Approve production and private upload':
      'Aprobar producción y subida privada',
  'Produce and upload privately (180-second target)':
      'Producir y subir en privado (meta de 180 segundos)',
  'Use the configured Korean girl-character AI voice without a new listening review.':
      'Usar la voz de IA configurada del personaje de niña en coreano sin una nueva revisión de audio.',
  'Korean · source recipe → script review → production and checks → private upload':
      'Coreano · receta original → revisar guion → producir y verificar → subir en privado',
  'Preserve source ingredients and cooking order. Fast production targets 180 seconds from accepted request to confirmed private upload, including queue and external delays. Show actual elapsed time. No automatic public publishing or paid retries.':
      'Se conservan los ingredientes y el orden original. La producción rápida tiene una meta de 180 segundos desde la solicitud aceptada hasta confirmar la subida privada, incluidas las esperas. Se muestra el tiempo real. Sin publicación pública ni reintentos de pago automáticos.',
  'Produce the reviewed script using the configured AI voice, then upload privately in the same run after picture, audio and duration checks. Do not wait for a separate video review. Target 180 seconds from acceptance to upload confirmation, including external waiting. Ask before uploading videos lasting three minutes or more.':
      'Producir el guion revisado con la voz de IA configurada y subirlo en privado en la misma ejecución tras verificar imagen, audio y duración. No se espera otra revisión del video. La meta es de 180 segundos con esperas incluidas. Se pide confirmación si el video dura tres minutos o más.',
  'Produce ingredient cards and cooking sketches without paid image generation. After script review, fast production targets 180 seconds through private upload and reports actual time including external waiting.':
      'Crear fichas de ingredientes y bocetos de cocina sin generar imágenes de pago. Tras revisar el guion, la meta es de 180 segundos hasta subir en privado, con el tiempo real y las esperas incluidos.',
  'Three-minute target met': 'Meta de tres minutos cumplida',
  'Three-minute target exceeded': 'Se superó la meta de tres minutos',
  'Target not confirmed': 'Meta sin confirmar',
  'Including waiting time': 'Incluye el tiempo de espera',
  'This video lasts three minutes or more. Confirm whether to continue uploading.':
      'El video dura tres minutos o más. Confirma si deseas continuar con la subida.',
  'Video ready · total elapsed time is confirmed after private upload.':
      'Video listo · el tiempo total se confirma después de subirlo en privado.',
  'Total elapsed time not yet confirmed': 'Tiempo total aún sin confirmar',
  'Fast production is not ready. Existing review production remains available.':
      'La producción rápida aún no está lista. La producción con revisión sigue disponible.',
  'Approve private upload after production to continue.':
      'Aprueba la subida privada después de producir para continuar.',
  'Request accepted → private upload {0} seconds · Three-minute target met':
      'Solicitud aceptada → subida privada: {0} segundos · meta de tres minutos cumplida',
  'Request accepted → private upload {0} seconds · Three-minute target exceeded':
      'Solicitud aceptada → subida privada: {0} segundos · se superó la meta de tres minutos',
  'Request accepted → private upload {0} seconds · Target not confirmed':
      'Solicitud aceptada → subida privada: {0} segundos · meta sin confirmar',
  '{0} seconds since request · Including waiting time':
      '{0} segundos desde la solicitud · incluye la espera',
  '{0} seconds since request · Three-minute target exceeded':
      '{0} segundos desde la solicitud · se superó la meta de tres minutos',
  'Video processing {0} seconds · total upload time not yet measured':
      'Procesamiento del video: {0} segundos · el tiempo total de subida aún no se ha medido',
  "Automatically prepare a script from a video URL":
      "Preparar un guion automáticamente desde una URL de video",
  "Enter the dish and source YouTube URL. If source information is missing, check up to five Korean videos of the same dish and select one with a published recipe. Stop if none qualifies.":
      "Introduce el plato y la URL de YouTube. Si falta información, se revisan hasta cinco videos en coreano del mismo plato y se elige uno con la receta publicada. Si ninguno cumple los requisitos, se detiene.",
  "The requested video lacks source information. The reference was changed to a Korean video of the same dish with a published recipe. Review the selected video and script below.":
      "El video solicitado no tiene suficiente información. Se eligió como referencia otro video en coreano del mismo plato con la receta publicada. Revisa el video seleccionado y el guion a continuación.",
  "Originally requested video": "Video solicitado originalmente",
  "Check the YouTube video URL.": "Comprueba la URL del video de YouTube.",
  "Confirm script preparation costs next. Video production and upload have not started.":
      "Confirma el costo del guion en la siguiente pantalla. La producción y la subida aún no han comenzado.",
  "Prepare script automatically": "Preparar guion automáticamente",
  "Could not check script status. Refresh and check again.":
      "No se pudo comprobar el guion. Actualiza y vuelve a comprobar.",
  "Immediate execution requested. Refresh to check progress.":
      "Se solicitó la ejecución inmediata. Actualiza para ver el progreso.",
  "The task is saved but immediate execution is unconfirmed. Scheduled execution may take time; do not submit another production request.":
      "La tarea está guardada pero la ejecución inmediata no se ha confirmado. La ejecución programada puede tardar; no envíes otra solicitud.",
  "Use the existing Korean female voice without listening to a new sample.":
      "Usar la voz femenina coreana existente sin escuchar una nueva muestra.",
  "Produce automatically from the reviewed script":
      "Producir automáticamente con el guion revisado",
  "Enter original text manually": "Introducir el texto original manualmente",
  "Produce one Korean video up to three minutes from the original recipe.":
      "Producir un video en coreano de hasta tres minutos basado en la receta original.",
  "Hello. Today we will follow the quantities and steps in the original video.":
      "Hola. Hoy seguiremos las cantidades y los pasos del video original.",
  "Follow each step with the ingredient list and original video.":
      "Sigue cada paso con la lista de ingredientes y el video original.",
  "Original YouTube URL": "URL original de YouTube",
  "Original video title": "Título del video original",
  "Channel name": "Nombre del canal",
  "Original serving size": "Porciones de la receta original",
  "Ingredients and original quantities, one per line":
      "Ingredientes y cantidades originales, uno por línea",
  "Original cooking steps, one per line":
      "Pasos originales de preparación, uno por línea",
  "Introduction": "Introducción",
  "Closing narration": "Narración final",
  "Plan a source-based video up to three minutes":
      "Planificar un video de hasta tres minutos basado en la fuente",
  "Copy original quantities, units, options and steps without alteration. Keep approximate amounts as written. Saving is free; confirm costs before voice or video production.":
      "Copia las cantidades, unidades, opciones y pasos originales sin cambios. Conserva las cantidades aproximadas. Guardar es gratis; confirma el costo antes de producir voz o video.",
  "Enter the original content.": "Introduce el contenido original.",
  "Enter 2 to 24 ingredient lines, up to 100 characters each.":
      "Introduce de 2 a 24 líneas de ingredientes, hasta 100 caracteres cada una.",
  "Enter 1 to 12 cooking steps, up to 160 characters each.":
      "Introduce de 1 a 12 pasos, hasta 160 caracteres cada uno.",
  "I checked the ingredients, quantities, units, options and steps against the original video.":
      "Comparé los ingredientes, cantidades, unidades, opciones y pasos con el video original.",
  "Use ingredient and cooking cards without new illustrations. Target processing is five minutes after script review; services and queues can add delays.":
      "Usa tarjetas de ingredientes y preparación sin ilustraciones nuevas. La meta es cinco minutos tras revisar el guion; los servicios y las colas pueden causar demoras.",
  "Warm, clear Korean female presenter. Preserve the original quantities and cooking order.":
      "Presentadora coreana con voz cálida y clara. Conserva las cantidades y el orden originales.",
  "Save script": "Guardar guion",
  "Could not open the original video. Check the URL.":
      "No se pudo abrir el video original. Comprueba la URL.",
  "Korean recipe studio": "Estudio de recetas en coreano",
  "Korean: source recipe, script review, voice, video review up to three minutes":
      "Coreano: receta original, revisión del guion, voz y revisión del video de hasta tres minutos",
  "Preserve original ingredients and steps. Target processing is five minutes; track queue and service delays separately. No automatic public posts or paid retries.":
      "Conserva los ingredientes y pasos originales. La meta es cinco minutos; registra las demoras por separado. No se publica ni se repiten tareas pagadas automáticamente.",
  "Plan three minutes from a YouTube source":
      "Planificar tres minutos desde una fuente de YouTube",
  "Legacy one-minute pilot": "Prueba anterior de un minuto",
  "Open the original YouTube reference": "Abrir el video original de YouTube",
  "Produce source recipe video, up to three minutes":
      "Producir un video de la receta original de hasta tres minutos",
  "Five-minute target met": "Meta de cinco minutos cumplida",
  "Five-minute target not confirmed": "Meta de cinco minutos sin confirmar",
  "Recipe videos: scripts and completed previews":
      "Videos de recetas: guiones y vistas previas terminadas",
  "Use the original YouTube ingredients and steps, and find finished previews here.":
      "Usa los ingredientes y pasos originales de YouTube y consulta aquí las vistas previas terminadas.",
  "Open script editing and production": "Abrir edición de guion y producción",
  "Open the studio to check admin authentication and connection.":
      "Abre el estudio para comprobar la autenticación y la conexión.",
  "Could not open the preview. Check it in the studio.":
      "No se pudo abrir la vista previa. Compruébala en el estudio.",
  "Recipe production and completed videos":
      "Producción de recetas y videos terminados",
  "Korean one-minute production": "Producción de un minuto en coreano",
  "Korean one-minute studio": "Estudio de un minuto en coreano",
  "New dish · one minute in Korean": "Nuevo plato · un minuto en coreano",
  "An elegant Korean grandmother with a warm, clear female voice and gentle humor. Do not imitate a real person.":
      "Una abuela coreana elegante, con voz femenina cálida y clara y humor suave. No imitar a una persona real.",
  "Korean series": "Serie en coreano",
  "A Korean series is required.": "Se necesita una serie en coreano.",
  "Enter the dish name.": "Ingresa el nombre del plato.",
  "Presenter, voice and story guidelines":
      "Presentadora, voz y pautas de la historia",
  "Enter the guidelines.": "Ingresa las pautas.",
  "Saving a plan is free. Paid tasks start separately after estimate confirmation.":
      "Guardar un plan es gratis. Las tareas de pago se inician por separado después de confirmar la estimación.",
  "Confirm private upload": "Confirmar subida privada",
  "Confirm task cost": "Confirmar costo de la tarea",
  "Estimated reservation: USD": "Reserva estimada: USD",
  "This is not a billing cap. Failed jobs retain their reservations and are not retried automatically.":
      "Esto no es un límite de facturación. Los trabajos fallidos conservan sus reservas y no se reintentan automáticamente.",
  "Generate only a short voice sample for the first scene.":
      "Generar solo una muestra breve de voz para la primera escena.",
  "Produce one 60-second Korean video.":
      "Producir un video de 60 segundos en coreano.",
  "Upload only the reviewed video as private.":
      "Subir solo el video revisado como privado.",
  "Research sources and write a Korean script.":
      "Investigar fuentes y escribir un guion en coreano.",
  "Could not open the preview. Please try again.":
      "No se pudo abrir la vista previa. Inténtalo de nuevo.",
  "Edit Korean script": "Editar guion en coreano",
  "Editing clears the previous voice sample approval. Source references are retained.":
      "Editar elimina la aprobación anterior de la muestra de voz. Se conservan las referencias a las fuentes.",
  "Narration": "Narración",
  "Enter the script.": "Ingresa el guion.",
  "On-screen text": "Texto en pantalla",
  "Enter the on-screen text.": "Ingresa el texto en pantalla.",
  "Korean only · 60 seconds · script → voice sample → video → private review":
      "Solo coreano · 60 segundos · guion → muestra de voz → video → revisión privada",
  "Production server connected": "Servidor de producción conectado",
  "Awaiting production connection · new paid tasks are locked.":
      "Esperando conexión de producción · las nuevas tareas de pago están bloqueadas.",
  "Three- and five-minute formats will follow stabilization. Public posting and paid retries are never automatic.":
      "Los formatos de tres y cinco minutos se añadirán tras estabilizar el sistema. La publicación pública y los reintentos de pago nunca son automáticos.",
  "Check the same request": "Consultar la misma solicitud",
  "Plan a new dish": "Planificar un nuevo plato",
  "First create a Korean series in the existing studio.":
      "Primero crea una serie en coreano en el estudio existente.",
  "Estimated reservation USD": "Reserva estimada USD",
  "Research and write script": "Investigar y escribir guion",
  "Edit script": "Editar guion",
  "I reviewed the script and sources for the food information.":
      "Revisé el guion y las fuentes de la información gastronómica.",
  "Create first-scene voice sample":
      "Crear muestra de voz de la primera escena",
  "Listen to voice sample": "Escuchar muestra de voz",
  "I listened and checked pronunciation, pace and voice.":
      "Escuché y comprobé la pronunciación, el ritmo y la voz.",
  "Use this voice": "Usar esta voz",
  "Preparing a real app guide screen · paid video production has not started.":
      "Preparando una captura real de la aplicación · la producción de video de pago no ha comenzado.",
  "Produce Korean 60-second video": "Producir video de 60 segundos en coreano",
  "Preview video": "Vista previa del video",
  "I reviewed the video, voice, captions and music.":
      "Revisé el video, la voz, los subtítulos y la música.",
  "Private upload": "Subida privada",
  "The task may have failed or its response may be lost. No automatic retry; check the job history and saved files.":
      "La tarea puede haber fallado o su respuesta puede haberse perdido. No se reintentará automáticamente; revisa el historial y los archivos guardados.",
  "Job history": "Historial de trabajos",
  "Scene {0} · {1}–{2} seconds": "Escena {0} · {1}–{2} segundos",
};
