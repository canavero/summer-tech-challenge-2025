@echo off
title LocPay Tech Challenge
color 0A

:: Protecao para execucao duplicada
if exist "nestjs-template-guia.md" (
    set ALREADY_RAN=1
) else if exist "express-template-guia.md" (
    set ALREADY_RAN=1
) else (
    set ALREADY_RAN=0
)

if "%ALREADY_RAN%"=="1" (
    echo O script ja foi executado anteriormente.
    echo Para executar novamente, restaure os templates originais antes com git restore .
    pause
    exit /b 1
)

echo.
echo  Bem-vindo(a) ao LocPay Tech Challenge
echo.
echo Escolha qual template voce deseja usar:
echo.
echo 1^) NestJS + Prisma + SQLite
echo 2^) ExpressJS + SQLite
echo.

set /p choice=Digite o numero da sua escolha [1-2]: 
echo.

if "%choice%"=="1" (
    set "SELECTED=nestjs-template"
) else if "%choice%"=="2" (
    set "SELECTED=express-template"
) else (
    echo Opcao invalida. Execute novamente e escolha 1 ou 2.
    pause
    exit /b 1
)

echo  Voce escolheu: %SELECTED%
echo.

:: Remove o template nao escolhido, se existir
for %%d in (nestjs-template express-template) do (
    if not "%%d"=="%SELECTED%" (
        if exist "%%d" (
            echo 🧹 Removendo %%d ...
            rmdir /s /q "%%d"
        )
    )
)

:: Move os arquivos do template escolhido para a raiz, se a pasta existir
if exist "%SELECTED%" (
    echo Movendo arquivos de %SELECTED% para a raiz...
    pushd "%SELECTED%"
    for /f "delims=" %%A in ('dir /b /a') do (
        move "%%A" "..\" >nul
    )
    popd
    rmdir /s /q "%SELECTED%"
)

:: Define o arquivo de guia
set "MD_SELECTED=%SELECTED%-guia.md"

echo.
echo Configuracao concluida!
echo Agora basta seguir as instrucoes do %MD_SELECTED%.
echo.
pause
