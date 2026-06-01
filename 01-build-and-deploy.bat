@echo off
REM Script para build y deploy de aplicación Mulesoft
REM Lee los valores del POM.xml y ejecuta los comandos necesarios

setlocal enabledelayedexpansion

REM Verificar que existe el archivo pom.xml
if not exist "pom.xml" (
    echo [ERROR] No se encontró el archivo pom.xml en el directorio actual
    exit /b 1
)

REM Extraer valores del POM.xml usando comandos de Maven
echo [INFO] Extrayendo información del pom.xml...

for /f "delims=" %%i in ('mvn help:evaluate -Dexpression^=project.groupId -q -DforceStdout') do set GROUP_ID=%%i
for /f "delims=" %%i in ('mvn help:evaluate -Dexpression^=project.artifactId -q -DforceStdout') do set ARTIFACT_ID=%%i
for /f "delims=" %%i in ('mvn help:evaluate -Dexpression^=project.version -q -DforceStdout') do set VERSION=%%i
for /f "delims=" %%i in ('mvn help:evaluate -Dexpression^=project.distributionManagement.repository.id -q -DforceStdout') do set REPOSITORY_ID=%%i
for /f "delims=" %%i in ('mvn help:evaluate -Dexpression^=project.distributionManagement.repository.url -q -DforceStdout') do set REPOSITORY_URL=%%i

REM Validar que se extrajeron los valores
if "%GROUP_ID%"=="" (
    echo [ERROR] No se pudieron extraer los valores del pom.xml
    exit /b 1
)
if "%ARTIFACT_ID%"=="" (
    echo [ERROR] No se pudieron extraer los valores del pom.xml
    exit /b 1
)
if "%VERSION%"=="" (
    echo [ERROR] No se pudieron extraer los valores del pom.xml
    exit /b 1
)

echo [INFO] Configuración detectada:
echo   GroupId: %GROUP_ID%
echo   ArtifactId: %ARTIFACT_ID%
echo   Version: %VERSION%
echo   Repository ID: %REPOSITORY_ID%
echo   Repository URL: %REPOSITORY_URL%
echo.

REM Ruta del archivo de propiedades
set PROPERTIES_FILE=src\main\resources\config\common.properties

REM Verificar que existe el archivo de propiedades
if not exist "%PROPERTIES_FILE%" (
    echo [ERROR] No se encontró el archivo %PROPERTIES_FILE%
    exit /b 1
)

REM Leer la versión actual
echo [INFO] Leyendo versión actual de %PROPERTIES_FILE%...
for /f "tokens=2 delims==" %%a in ('findstr /r "^ce\.version=" "%PROPERTIES_FILE%"') do set CURRENT_VERSION=%%a
set CURRENT_VERSION=%CURRENT_VERSION: =%

if "%CURRENT_VERSION%"=="" (
    echo [ERROR] No se encontró la propiedad ce.version en %PROPERTIES_FILE%
    exit /b 1
)

echo [INFO] Versión actual: %CURRENT_VERSION%

REM Extraer los componentes de la versión (MAJOR.MINOR.PATCH)
for /f "tokens=1,2,3 delims=." %%a in ("%CURRENT_VERSION%") do (
    set MAJOR=%%a
    set MINOR=%%b
    set PATCH=%%c
)

REM Incrementar el PATCH
set /a NEW_PATCH=%PATCH%+1
set NEW_VERSION=%MAJOR%.%MINOR%.%NEW_PATCH%

echo [INFO] Nueva versión: %NEW_VERSION%

REM Actualizar el archivo de propiedades
echo [INFO] Actualizando %PROPERTIES_FILE%...
copy "%PROPERTIES_FILE%" "%PROPERTIES_FILE%.bak" >nul

REM Usar PowerShell para la búsqueda y reemplazo
powershell -Command "(Get-Content '%PROPERTIES_FILE%') -replace '^ce\.version=.*', 'ce.version=%NEW_VERSION%' | Set-Content '%PROPERTIES_FILE%'"

REM Verificar que se actualizó correctamente
for /f "tokens=2 delims==" %%a in ('findstr /r "^ce\.version=" "%PROPERTIES_FILE%"') do set UPDATED_VERSION=%%a
set UPDATED_VERSION=%UPDATED_VERSION: =%

if not "%UPDATED_VERSION%"=="%NEW_VERSION%" (
    echo [ERROR] No se pudo actualizar la versión en %PROPERTIES_FILE%
    move /y "%PROPERTIES_FILE%.bak" "%PROPERTIES_FILE%" >nul
    exit /b 1
)

echo [INFO] Versión actualizada de %CURRENT_VERSION% a %NEW_VERSION%

REM Commit del cambio en Git
echo [INFO] Haciendo commit del cambio de versión...

REM Verificar que estamos en un repositorio git
if not exist ".git" (
    echo [WARNING] No se detectó repositorio Git. Se omitirá el commit.
) else (
    git add "%PROPERTIES_FILE%"
    git commit -m "deploy %NEW_VERSION%"
    if errorlevel 1 (
        echo [WARNING] No se pudo hacer commit (quizás no hay cambios o hay conflictos^)
    ) else (
        echo [INFO] Commit realizado: deploy %NEW_VERSION%
    )
)

REM Nombres de archivos
set MULE_APP_JAR=%ARTIFACT_ID%-%VERSION%-mule-application.jar
set TARGET_JAR=%ARTIFACT_ID%-%VERSION%.jar

REM Limpiar y empaquetar
echo [INFO] Ejecutando mvn clean package...
call mvn clean package

if errorlevel 1 (
    echo [ERROR] Falló el comando mvn clean package
    exit /b 1
)

REM Verificar que se generó el archivo
if not exist "target\%MULE_APP_JAR%" (
    echo [ERROR] No se generó el archivo target\%MULE_APP_JAR%
    exit /b 1
)

REM Copiar y renombrar el archivo
echo [INFO] Copiando %MULE_APP_JAR% a %TARGET_JAR%...
copy "target\%MULE_APP_JAR%" "target\%TARGET_JAR%" >nul

if errorlevel 1 (
    echo [ERROR] Falló la copia del archivo
    exit /b 1
)

REM Deploy al repositorio
echo [INFO] Deployando al repositorio %REPOSITORY_URL%...
call mvn deploy:deploy-file -DgroupId="%GROUP_ID%" -DartifactId="%ARTIFACT_ID%" -Dversion="%VERSION%" -DrepositoryId="%REPOSITORY_ID%" -Dpackaging=jar -Dfile="target\%TARGET_JAR%" -Durl="%REPOSITORY_URL%"

if errorlevel 1 (
    echo [ERROR] Falló el deploy al repositorio
    exit /b 1
)

echo [INFO] Deploy completado exitosamente!
echo [INFO] Artefacto deployado: %GROUP_ID%:%ARTIFACT_ID%:%VERSION%
echo [INFO] Versión en common.properties: %NEW_VERSION%
echo.
echo [INFO] Recuerda hacer 'git push' para subir el commit al repositorio remoto

endlocal
