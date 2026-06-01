#!/bin/bash

# Script para build y deploy de aplicación Mulesoft
# Lee los valores del POM.xml y ejecuta los comandos necesarios

set -e  # Detener el script si ocurre algún error

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Función para imprimir mensajes
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Verificar que existe el archivo pom.xml
if [ ! -f "pom.xml" ]; then
    log_error "No se encontró el archivo pom.xml en el directorio actual"
    exit 1
fi

# Extraer valores del POM.xml usando comandos de Maven
log_info "Extrayendo información del pom.xml..."

GROUP_ID=$(mvn help:evaluate -Dexpression=project.groupId -q -DforceStdout)
ARTIFACT_ID=$(mvn help:evaluate -Dexpression=project.artifactId -q -DforceStdout)
VERSION=$(mvn help:evaluate -Dexpression=project.version -q -DforceStdout)
REPOSITORY_ID=$(mvn help:evaluate -Dexpression=project.distributionManagement.repository.id -q -DforceStdout)
REPOSITORY_URL=$(mvn help:evaluate -Dexpression=project.distributionManagement.repository.url -q -DforceStdout)

# Validar que se extrajeron los valores
if [ -z "$GROUP_ID" ] || [ -z "$ARTIFACT_ID" ] || [ -z "$VERSION" ]; then
    log_error "No se pudieron extraer los valores del pom.xml"
    exit 1
fi

log_info "Configuración detectada:"
echo "  GroupId: $GROUP_ID"
echo "  ArtifactId: $ARTIFACT_ID"
echo "  Version: $VERSION"
echo "  Repository ID: $REPOSITORY_ID"
echo "  Repository URL: $REPOSITORY_URL"
echo ""

# Ruta del archivo de propiedades
PROPERTIES_FILE="src/main/resources/config/common.properties"

# Verificar que existe el archivo de propiedades
if [ ! -f "$PROPERTIES_FILE" ]; then
    log_error "No se encontró el archivo $PROPERTIES_FILE"
    exit 1
fi

# Paso 1: Incrementar la versión en common.properties
log_info "Leyendo versión actual de $PROPERTIES_FILE..."

# Leer la versión actual
CURRENT_VERSION=$(grep -E '^ce\.version=' "$PROPERTIES_FILE" | cut -d'=' -f2 | tr -d '[:space:]')

if [ -z "$CURRENT_VERSION" ]; then
    log_error "No se encontró la propiedad ce.version en $PROPERTIES_FILE"
    exit 1
fi

log_info "Versión actual: $CURRENT_VERSION"

# Extraer los componentes de la versión (MAJOR.MINOR.PATCH)
MAJOR=$(echo "$CURRENT_VERSION" | cut -d'.' -f1)
MINOR=$(echo "$CURRENT_VERSION" | cut -d'.' -f2)
PATCH=$(echo "$CURRENT_VERSION" | cut -d'.' -f3)

# Incrementar el PATCH
NEW_PATCH=$((PATCH + 1))
NEW_VERSION="${MAJOR}.${MINOR}.${NEW_PATCH}"

log_info "Nueva versión: $NEW_VERSION"

# Actualizar el archivo de propiedades
log_info "Actualizando $PROPERTIES_FILE..."
sed -i.bak "s/^ce\.version=.*/ce.version=$NEW_VERSION/" "$PROPERTIES_FILE"

# Verificar que se actualizó correctamente
UPDATED_VERSION=$(grep -E '^ce\.version=' "$PROPERTIES_FILE" | cut -d'=' -f2 | tr -d '[:space:]')
if [ "$UPDATED_VERSION" != "$NEW_VERSION" ]; then
    log_error "No se pudo actualizar la versión en $PROPERTIES_FILE"
    mv "${PROPERTIES_FILE}.bak" "$PROPERTIES_FILE"  # Restaurar backup
    exit 1
fi

log_info "✓ Versión actualizada de $CURRENT_VERSION a $NEW_VERSION"

# Paso 2: Commit del cambio en Git
log_info "Haciendo commit del cambio de versión..."

# Verificar que estamos en un repositorio git
if [ ! -d ".git" ]; then
    log_warning "No se detectó repositorio Git. Se omitirá el commit."
else
    git add "$PROPERTIES_FILE"
    git commit -m "deploy $NEW_VERSION"
    
    if [ $? -ne 0 ]; then
        log_warning "No se pudo hacer commit (quizás no hay cambios o hay conflictos)"
    else
        log_info "✓ Commit realizado: deploy $NEW_VERSION"
    fi
fi

# Nombres de archivos
MULE_APP_JAR="${ARTIFACT_ID}-${VERSION}-mule-application.jar"
TARGET_JAR="${ARTIFACT_ID}-${VERSION}.jar"

# Paso 3: Limpiar y empaquetar
log_info "Ejecutando mvn clean package..."
mvn clean package

if [ $? -ne 0 ]; then
    log_error "Falló el comando mvn clean package"
    exit 1
fi

# Verificar que se generó el archivo
if [ ! -f "target/$MULE_APP_JAR" ]; then
    log_error "No se generó el archivo target/$MULE_APP_JAR"
    exit 1
fi

# Paso 4: Copiar y renombrar el archivo
log_info "Copiando $MULE_APP_JAR a $TARGET_JAR..."
cp "target/$MULE_APP_JAR" "target/$TARGET_JAR"

if [ $? -ne 0 ]; then
    log_error "Falló la copia del archivo"
    exit 1
fi

# Paso 5: Deploy al repositorio
log_info "Deployando al repositorio $REPOSITORY_URL..."
mvn deploy:deploy-file \
    -DgroupId="$GROUP_ID" \
    -DartifactId="$ARTIFACT_ID" \
    -Dversion="$VERSION" \
    -DrepositoryId="$REPOSITORY_ID" \
    -Dpackaging=jar \
    -Dfile="target/$TARGET_JAR" \
    -Durl="$REPOSITORY_URL"

if [ $? -ne 0 ]; then
    log_error "Falló el deploy al repositorio"
    exit 1
fi

log_info "✓ Deploy completado exitosamente!"
log_info "Artefacto deployado: $GROUP_ID:$ARTIFACT_ID:$VERSION"
log_info "Versión en common.properties: $NEW_VERSION"
echo ""
log_info "Recuerda hacer 'git push' para subir el commit al repositorio remoto"