<#
.SYNOPSIS
    Interface Grafica (GUI) moderna em WPF para o TF-Toolkit (Tech Fontes)
    com suporte a tema Auto / Claro / Escuro.
#>
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$BaseDir = $PSScriptRoot
if (-not $BaseDir) { $BaseDir = Split-Path -Parent $MyInvocation.MyCommand.Definition }

# Carregar configuracoes
$ConfigFile = Join-Path $BaseDir "Config\settings.json"
$Config = $null
$OutputFolder = "C:\ProgramData\Preventiva"
if (Test-Path -LiteralPath $ConfigFile) {
    try {
        $Config = Get-Content -LiteralPath $ConfigFile -Encoding UTF8 -Raw | ConvertFrom-Json
        if ($Config.ReportSettings -and $Config.ReportSettings.OutputFolder) {
            $OutputFolder = $Config.ReportSettings.OutputFolder
        }
    } catch {}
}

$NetworkMod = Join-Path $BaseDir "Modules\NetworkTools.psm1"
if (Test-Path -LiteralPath $NetworkMod) {
    try { Import-Module $NetworkMod -Force -ErrorAction SilentlyContinue } catch {}
}
# Dados rapidos da maquina para o cabecalho
$HostName = $env:COMPUTERNAME
$FreeGB = try { [math]::Round((Get-PSDrive C).Free / 1GB, 1) } catch { "?" }
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

[xml]$XAML = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Tech Fontes - Preventiva Corporativa"
        Height="720" Width="960" MinHeight="690" MinWidth="900"
        WindowStartupLocation="CenterScreen"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        FontFamily="Segoe UI">

    <Window.Resources>
        <!-- Paleta Dinamica (alternada em tempo real entre Escuro e Claro) -->
        <SolidColorBrush x:Key="BgWindow" Color="#141419"/>
        <SolidColorBrush x:Key="BgHeader" Color="#101015"/>
        <SolidColorBrush x:Key="BgCard" Color="#1d1e26"/>
        <SolidColorBrush x:Key="BgSubCard" Color="#161821"/>
        <SolidColorBrush x:Key="BgFooter" Color="#191b24"/>
        <SolidColorBrush x:Key="BgControl" Color="#171820"/>
        <SolidColorBrush x:Key="BgControlHover" Color="#222430"/>
        <SolidColorBrush x:Key="BgControlSelected" Color="#242026"/>
        <SolidColorBrush x:Key="BgControlCheckedGreen" Color="#1d2824"/>
        <SolidColorBrush x:Key="BgSecondaryBtn" Color="#242736"/>
        <SolidColorBrush x:Key="BgSecondaryBtnHover" Color="#30354a"/>
        <SolidColorBrush x:Key="BgTab" Color="#1b1d26"/>
        <SolidColorBrush x:Key="BgTabHover" Color="#252836"/>
        <SolidColorBrush x:Key="BgPill" Color="#1d1f2a"/>
        <SolidColorBrush x:Key="BgTitleHover" Color="#2a2c38"/>
        <SolidColorBrush x:Key="BgBadgeAdmin" Color="#1d2a23"/>
        <SolidColorBrush x:Key="BorderWindow" Color="#2f3242"/>
        <SolidColorBrush x:Key="BorderSubtle" Color="#2b2d3a"/>
        <SolidColorBrush x:Key="BorderControl" Color="#2b2e3d"/>
        <SolidColorBrush x:Key="BorderControlHover" Color="#484d66"/>
        <SolidColorBrush x:Key="BorderBadgeAdmin" Color="#2f523e"/>
        <SolidColorBrush x:Key="TextPrimary" Color="#f0f0f5"/>
        <SolidColorBrush x:Key="TextSecondary" Color="#c9cde0"/>
        <SolidColorBrush x:Key="TextMuted" Color="#8f93a8"/>
        <SolidColorBrush x:Key="TextWarning" Color="#d99a7c"/>
        <SolidColorBrush x:Key="TextGood" Color="#7ad19f"/>
        <SolidColorBrush x:Key="ScrollThumb" Color="#383c52"/>

        <!-- Cores Fixas da Identidade Tech Fontes -->
        <SolidColorBrush x:Key="AccentOrange" Color="#C4613A"/>
        <SolidColorBrush x:Key="AccentOrangeHover" Color="#d97248"/>
        <SolidColorBrush x:Key="AccentGreen" Color="#3d7a5a"/>
        <SolidColorBrush x:Key="AccentGreenHover" Color="#4d9970"/>

        <!-- Botao Janela (Minimizar / Fechar) -->
        <Style TargetType="Button" x:Key="TitleBarButton">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="{DynamicResource TextMuted}"/>
            <Setter Property="Width" Value="36"/>
            <Setter Property="Height" Value="30"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="6">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="{DynamicResource BgTitleHover}"/>
                                <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style TargetType="Button" x:Key="CloseButton" BasedOn="{StaticResource TitleBarButton}">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="6">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="#b83b3b"/>
                                <Setter Property="Foreground" Value="White"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Botao Pill de Tema (Auto / Claro / Escuro) -->
        <Style TargetType="Button" x:Key="ThemePillButton">
            <Setter Property="Background" Value="{DynamicResource BgPill}"/>
            <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BorderSubtle}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="11,4"/>
            <Setter Property="FontSize" Value="11.5"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bd" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="14">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="{TemplateBinding Padding}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="{DynamicResource BgControlHover}"/>
                                <Setter TargetName="bd" Property="BorderBrush" Value="#C4613A"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Botao Primario (Executar) -->
        <Style TargetType="Button" x:Key="RunButton">
            <Setter Property="Background" Value="{StaticResource AccentGreen}"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="Padding" Value="20,10"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="8">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="{TemplateBinding Padding}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="{StaticResource AccentGreenHover}"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.45"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Botao Secundario -->
        <Style TargetType="Button" x:Key="SecondaryButton">
            <Setter Property="Background" Value="{DynamicResource BgSecondaryBtn}"/>
            <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
            <Setter Property="FontSize" Value="12.5"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="14,8"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BorderControl}"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bd" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="7">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="{TemplateBinding Padding}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="{DynamicResource BgSecondaryBtnHover}"/>
                                <Setter TargetName="bd" Property="BorderBrush" Value="#5c7ea8"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.45"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Botao Preset -->
        <Style TargetType="Button" x:Key="PresetButton">
            <Setter Property="Background" Value="{DynamicResource BgSecondaryBtn}"/>
            <Setter Property="Foreground" Value="{DynamicResource TextSecondary}"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="12,6"/>
            <Setter Property="Margin" Value="0,0,6,0"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BorderControl}"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bd" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="6">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="{TemplateBinding Padding}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="{DynamicResource BgSecondaryBtnHover}"/>
                                <Setter TargetName="bd" Property="BorderBrush" Value="#C4613A"/>
                                <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- TabControl & TabItem Customizados -->
        <Style TargetType="TabControl">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="0"/>
        </Style>

        <Style TargetType="TabItem">
            <Setter Property="Foreground" Value="{DynamicResource TextMuted}"/>
            <Setter Property="FontSize" Value="13.5"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Margin" Value="0,0,8,0"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TabItem">
                        <Border x:Name="TabBorder" Background="{DynamicResource BgTab}" BorderBrush="{DynamicResource BorderSubtle}" BorderThickness="1"
                                CornerRadius="8" Padding="18,10" SnapsToDevicePixels="True">
                            <ContentPresenter ContentSource="Header" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="TabBorder" Property="Background" Value="{DynamicResource BgTabHover}"/>
                                <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
                            </Trigger>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="TabBorder" Property="Background" Value="#C4613A"/>
                                <Setter TargetName="TabBorder" Property="BorderBrush" Value="#d97248"/>
                                <Setter Property="Foreground" Value="White"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- RadioButton em formato de Card Clicavel -->
        <Style TargetType="RadioButton" x:Key="CardRadio">
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Margin" Value="0,0,0,8"/>
            <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="RadioButton">
                        <Border x:Name="CardBorder" Background="{DynamicResource BgControl}" BorderBrush="{DynamicResource BorderControl}" BorderThickness="1.5"
                                CornerRadius="9" Padding="14,9" SnapsToDevicePixels="True">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="Auto"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>
                                <Grid Grid.Column="0" Width="18" Height="18" VerticalAlignment="Top" Margin="0,2,12,0">
                                    <Ellipse x:Name="OuterCircle" Stroke="#7a8099" StrokeThickness="2" Fill="Transparent"/>
                                    <Ellipse x:Name="InnerDot" Width="8" Height="8" Fill="#C4613A" Visibility="Collapsed"/>
                                </Grid>
                                <ContentPresenter Grid.Column="1" VerticalAlignment="Center"/>
                            </Grid>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="CardBorder" Property="Background" Value="{DynamicResource BgControlHover}"/>
                                <Setter TargetName="CardBorder" Property="BorderBrush" Value="{DynamicResource BorderControlHover}"/>
                            </Trigger>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="CardBorder" Property="Background" Value="{DynamicResource BgControlSelected}"/>
                                <Setter TargetName="CardBorder" Property="BorderBrush" Value="#C4613A"/>
                                <Setter TargetName="OuterCircle" Property="Stroke" Value="#C4613A"/>
                                <Setter TargetName="InnerDot" Property="Visibility" Value="Visible"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- CheckBox em formato de Card Clicavel (Softwares) -->
        <Style TargetType="CheckBox" x:Key="CardCheck">
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
            <Setter Property="Margin" Value="0,0,10,10"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="CheckBox">
                        <Border x:Name="CheckBorder" Background="{DynamicResource BgControl}" BorderBrush="{DynamicResource BorderControl}" BorderThickness="1.5"
                                CornerRadius="8" Padding="12,10" SnapsToDevicePixels="True">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="Auto"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>
                                <Border x:Name="Box" Grid.Column="0" Width="18" Height="18" CornerRadius="4"
                                        BorderBrush="#7a8099" BorderThickness="2" Background="Transparent"
                                        VerticalAlignment="Center" Margin="0,0,10,0">
                                    <TextBlock x:Name="CheckMark" Text="&#x2713;" Foreground="White" FontSize="12"
                                               FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center"
                                               Visibility="Collapsed"/>
                                </Border>
                                <ContentPresenter Grid.Column="1" VerticalAlignment="Center"/>
                            </Grid>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="CheckBorder" Property="Background" Value="{DynamicResource BgControlHover}"/>
                                <Setter TargetName="CheckBorder" Property="BorderBrush" Value="{DynamicResource BorderControlHover}"/>
                            </Trigger>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="CheckBorder" Property="Background" Value="{DynamicResource BgControlCheckedGreen}"/>
                                <Setter TargetName="CheckBorder" Property="BorderBrush" Value="#3d7a5a"/>
                                <Setter TargetName="Box" Property="Background" Value="#3d7a5a"/>
                                <Setter TargetName="Box" Property="BorderBrush" Value="#4d9970"/>
                                <Setter TargetName="CheckMark" Property="Visibility" Value="Visible"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- CheckBox Compacto para Checklist de Tarefas e Tweaks -->
        <Style TargetType="CheckBox" x:Key="TaskCheck">
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
            <Setter Property="Margin" Value="0,0,0,6"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="CheckBox">
                        <Border x:Name="TaskBorder" Background="{DynamicResource BgControl}" BorderBrush="{DynamicResource BorderControl}" BorderThickness="1"
                                CornerRadius="7" Padding="10,7" SnapsToDevicePixels="True">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="Auto"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>
                                <Border x:Name="Box" Grid.Column="0" Width="16" Height="16" CornerRadius="4"
                                        BorderBrush="#7a8099" BorderThickness="1.8" Background="Transparent"
                                        VerticalAlignment="Center" Margin="0,0,9,0">
                                    <TextBlock x:Name="CheckMark" Text="&#x2713;" Foreground="White" FontSize="11"
                                               FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center"
                                               Visibility="Collapsed"/>
                                </Border>
                                <ContentPresenter Grid.Column="1" VerticalAlignment="Center"/>
                            </Grid>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="TaskBorder" Property="Background" Value="{DynamicResource BgControlHover}"/>
                                <Setter TargetName="TaskBorder" Property="BorderBrush" Value="{DynamicResource BorderControlHover}"/>
                            </Trigger>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="TaskBorder" Property="Background" Value="{DynamicResource BgControlSelected}"/>
                                <Setter TargetName="TaskBorder" Property="BorderBrush" Value="#C4613A"/>
                                <Setter TargetName="Box" Property="Background" Value="#C4613A"/>
                                <Setter TargetName="Box" Property="BorderBrush" Value="#d97248"/>
                                <Setter TargetName="CheckMark" Property="Visibility" Value="Visible"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- ScrollBar Minimalista -->
        <Style TargetType="ScrollBar">
            <Setter Property="Width" Value="7"/>
            <Setter Property="MinWidth" Value="7"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ScrollBar">
                        <Grid Background="Transparent">
                            <Track Name="PART_Track" IsDirectionReversed="True">
                                <Track.Thumb>
                                    <Thumb>
                                        <Thumb.Template>
                                            <ControlTemplate TargetType="Thumb">
                                                <Border Background="{DynamicResource ScrollThumb}" CornerRadius="3.5" Margin="1,2"/>
                                            </ControlTemplate>
                                        </Thumb.Template>
                                    </Thumb>
                                </Track.Thumb>
                            </Track>
                        </Grid>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <!-- Moldura Externa -->
    <Border Background="{DynamicResource BgWindow}" BorderBrush="{DynamicResource BorderWindow}" BorderThickness="1" CornerRadius="12">
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <!-- Barra de Titulo Customizada (Arrastavel) -->
            <Border Name="TitleBar" Grid.Row="0" Background="{DynamicResource BgHeader}" CornerRadius="12,12,0,0"
                    BorderBrush="{DynamicResource BorderSubtle}" BorderThickness="0,0,0,1" Padding="18,9">
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                        <TextBlock Text="TECH FONTES" FontSize="11.5" FontWeight="Bold" Foreground="#C4613A"/>
                        <TextBlock Text="  &#x2022;  TF-TOOLKIT PREVENTIVA WINDOWS" FontSize="11.5" FontWeight="SemiBold" Foreground="{DynamicResource TextMuted}"/>
                    </StackPanel>
                    <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                        <!-- Seletor de Tema: Auto / Claro / Escuro -->
                        <Button Name="btnThemeToggle" Style="{StaticResource ThemePillButton}" Margin="0,0,10,0" ToolTip="Alternar tema: Auto (Windows), Claro ou Escuro">
                            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                <TextBlock Name="txtThemeIcon" Text="&#x263E;" FontSize="12.5" Foreground="#5b9dff" Margin="0,0,6,0" VerticalAlignment="Center"/>
                                <TextBlock Name="txtThemeLabel" Text="Escuro" VerticalAlignment="Center"/>
                            </StackPanel>
                        </Button>
                        <Button Name="btnMinimize" Content="&#x2014;" Style="{StaticResource TitleBarButton}" ToolTip="Minimizar"/>
                        <Button Name="btnClose" Content="&#x2715;" Style="{StaticResource CloseButton}" Margin="4,0,0,0" ToolTip="Fechar"/>
                    </StackPanel>
                </Grid>
            </Border>

            <!-- Cabecalho da Marca + Info da Maquina -->
            <Grid Grid.Row="1" Margin="24,18,24,12">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <Image Name="imgLogo" Grid.Column="0" Width="46" Height="46" Margin="0,0,14,0"
                       RenderOptions.BitmapScalingMode="HighQuality" VerticalAlignment="Center"/>

                <StackPanel Grid.Column="1" VerticalAlignment="Center">
                    <TextBlock FontSize="24" FontWeight="Bold" Foreground="{DynamicResource TextPrimary}">
                        <Run Text="Tech "/><Run Text="Fontes" Foreground="#C4613A"/>
                    </TextBlock>
                    <StackPanel Orientation="Horizontal" Margin="0,1,0,0">
                        <TextBlock Text="Central de Manuten&#x00E7;&#x00E3;o &amp; Diagn&#x00F3;stico  |  " FontSize="12.5" Foreground="{DynamicResource TextMuted}"/>
                        <TextBlock FontSize="12.5">
                            <Hyperlink Name="linkSite" Foreground="#4a7ab5" TextDecorations="None" Cursor="Hand">techfontes.com.br</Hyperlink>
                        </TextBlock>
                    </StackPanel>
                </StackPanel>

                <!-- Pilulas de Contexto da Maquina -->
                <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center">
                    <Border Background="{DynamicResource BgPill}" BorderBrush="{DynamicResource BorderSubtle}" BorderThickness="1" CornerRadius="8" Padding="12,7" Margin="0,0,8,0">
                        <StackPanel>
                            <TextBlock Text="ESTA&#x00C7;&#x00C3;O" FontSize="9.5" FontWeight="Bold" Foreground="{DynamicResource TextMuted}"/>
                            <TextBlock Name="txtHostName" Text="..." FontSize="12.5" FontWeight="SemiBold" Foreground="{DynamicResource TextPrimary}"/>
                        </StackPanel>
                    </Border>
                    <Border Background="{DynamicResource BgPill}" BorderBrush="{DynamicResource BorderSubtle}" BorderThickness="1" CornerRadius="8" Padding="12,7" Margin="0,0,8,0">
                        <StackPanel>
                            <TextBlock Text="LIVRE EM C:" FontSize="9.5" FontWeight="Bold" Foreground="{DynamicResource TextMuted}"/>
                            <TextBlock Name="txtFreeSpace" Text="... GB" FontSize="12.5" FontWeight="SemiBold" Foreground="{DynamicResource TextGood}"/>
                        </StackPanel>
                    </Border>
                    <Border Name="bdAdmin" Background="{DynamicResource BgBadgeAdmin}" BorderBrush="{DynamicResource BorderBadgeAdmin}" BorderThickness="1" CornerRadius="8" Padding="12,7">
                        <StackPanel>
                            <TextBlock Text="PRIVIL&#x00C9;GIO" FontSize="9.5" FontWeight="Bold" Foreground="{DynamicResource TextMuted}"/>
                            <TextBlock Name="txtAdmin" Text="Admin" FontSize="12.5" FontWeight="SemiBold" Foreground="{DynamicResource TextGood}"/>
                        </StackPanel>
                    </Border>
                </StackPanel>
            </Grid>

            <!-- Conteudo Principal (Abas) -->
            <TabControl Grid.Row="2" Margin="24,6,24,14">
                <!-- ABA 1: PREVENTIVA & DIAGNOSTICO -->
                <TabItem Header="Preventiva &amp; Diagn&#x00F3;stico">
                    <Grid Margin="0,14,0,0">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="1.55*"/>
                            <ColumnDefinition Width="16"/>
                            <ColumnDefinition Width="0.95*"/>
                        </Grid.ColumnDefinitions>

                        <!-- Coluna Esquerda: Presets + Checklist Granular -->
                        <Border Grid.Column="0" Background="{DynamicResource BgCard}" BorderBrush="{DynamicResource BorderSubtle}"
                                BorderThickness="1" CornerRadius="10" Padding="15">
                            <Grid>
                                <Grid.RowDefinitions>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="*"/>
                                </Grid.RowDefinitions>

                                <Grid Grid.Row="0" Margin="0,0,0,10">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBlock Text="1. Presets &amp; Tarefas da Manuten&#x00E7;&#x00E3;o" FontSize="14.5" FontWeight="Bold" Foreground="{DynamicResource TextPrimary}" VerticalAlignment="Center"/>
                                    <TextBlock Name="txtTasksCount" Grid.Column="1" Text="8 selecionadas" FontSize="11.5" FontWeight="SemiBold" Foreground="#C4613A" VerticalAlignment="Center"/>
                                </Grid>

                                <Grid Grid.Row="1" Margin="0,0,0,12">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <StackPanel Grid.Column="0" Orientation="Horizontal">
                                        <Button Name="btnPresetLight" Content="Light" Style="{StaticResource PresetButton}"/>
                                        <Button Name="btnPresetModerate" Content="Moderate" Style="{StaticResource PresetButton}"/>
                                        <Button Name="btnPresetHeavy" Content="Heavy" Style="{StaticResource PresetButton}"/>
                                        <Button Name="btnPresetRecovery" Content="Recovery" Style="{StaticResource PresetButton}"/>
                                    </StackPanel>
                                    <Button Name="btnPresetClear" Grid.Column="1" Content="Desmarcar tudo" Style="{StaticResource PresetButton}" Margin="0"/>
                                </Grid>

                                <!-- Checklist em 2 Colunas Simetricas (8 + 8) -->
                                <Grid Grid.Row="2">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="10"/>
                                        <ColumnDefinition Width="*"/>
                                    </Grid.ColumnDefinitions>

                                    <StackPanel Grid.Column="0">
                                        <TextBlock Text="B&#x00C1;SICO &amp; DIAGN&#x00D3;STICO" FontSize="10" FontWeight="Bold" Foreground="{DynamicResource TextMuted}" Margin="2,0,0,6"/>
                                        <CheckBox Name="chkTaskInventory" Tag="Inventory" Style="{StaticResource TaskCheck}" Content="Invent&#x00E1;rio, Bateria e Rede"/>
                                        <CheckBox Name="chkTaskDiskEvents" Tag="DiskEvents" Style="{StaticResource TaskCheck}" Content="Disco, Startup, Drivers e Eventos"/>
                                        <CheckBox Name="chkTaskCriticalServices" Tag="CriticalServices" Style="{StaticResource TaskCheck}" Content="Verificar Servi&#x00E7;os Cr&#x00ED;ticos"/>
                                        <CheckBox Name="chkTaskCleanTemp" Tag="CleanTemp" Style="{StaticResource TaskCheck}" Content="Limpeza de Tempor&#x00E1;rios"/>
                                        <CheckBox Name="chkTaskEmptyRecycleBin" Tag="EmptyRecycleBin" Style="{StaticResource TaskCheck}" Content="Esvaziar Lixeira"/>
                                        <CheckBox Name="chkTaskFlushDns" Tag="FlushDns" Style="{StaticResource TaskCheck}" Content="Flush DNS"/>
                                        <CheckBox Name="chkTaskFolderScan" Tag="FolderScan" Style="{StaticResource TaskCheck}" Content="Varredura de Pastas Grandes"/>
                                        <CheckBox Name="chkTaskSecurityAudit" Tag="SecurityAudit" Style="{StaticResource TaskCheck}" Content="Auditoria Seguran&#x00E7;a (AV/FW)" Margin="0"/>
                                    </StackPanel>

                                    <StackPanel Grid.Column="2">
                                        <TextBlock Text="AVAN&#x00C7;ADO &amp; REPAROS" FontSize="10" FontWeight="Bold" Foreground="{DynamicResource TextMuted}" Margin="2,0,0,6"/>
                                        <CheckBox Name="chkTaskWindowsUpdate" Tag="WindowsUpdate" Style="{StaticResource TaskCheck}" Content="Windows Update"/>
                                        <CheckBox Name="chkTaskDefenderScan" Tag="DefenderScan" Style="{StaticResource TaskCheck}" Content="Defender Quick Scan"/>
                                        <CheckBox Name="chkTaskTrim" Tag="Trim" Style="{StaticResource TaskCheck}" Content="Otimiza&#x00E7;&#x00E3;o SSD (TRIM)"/>
                                        <CheckBox Name="chkTaskIntegrity" Tag="Integrity" Style="{StaticResource TaskCheck}" Content="DISM + SFC /scannow"/>
                                        <CheckBox Name="chkTaskWinSxS" Tag="WinSxS" Style="{StaticResource TaskCheck}" Content="Limpeza WinSxS"/>
                                        <CheckBox Name="chkTaskFullFileScan" Tag="FullFileScan" Style="{StaticResource TaskCheck}" Content="Varredura Arquivos (&gt;200MB)"/>
                                        <CheckBox Name="chkTaskRestorePoint" Tag="RestorePoint" Style="{StaticResource TaskCheck}" Content="Criar Ponto de Restaura&#x00E7;&#x00E3;o"/>
                                        <CheckBox Name="chkTaskRecovery" Tag="Recovery" Style="{StaticResource TaskCheck}" Content="Recovery (Reset WU + Rede)" Margin="0"/>
                                    </StackPanel>
                                </Grid>
                            </Grid>
                        </Border>

                        <!-- Coluna Direita: Tipo de Execucao + Relatorios -->
                        <Border Grid.Column="2" Background="{DynamicResource BgCard}" BorderBrush="{DynamicResource BorderSubtle}"
                                BorderThickness="1" CornerRadius="10" Padding="16">
                            <Grid>
                                <Grid.RowDefinitions>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="*"/>
                                    <RowDefinition Height="Auto"/>
                                </Grid.RowDefinitions>

                                <TextBlock Grid.Row="0" Text="2. Tipo de Execu&#x00E7;&#x00E3;o" FontSize="14.5" FontWeight="Bold" Foreground="{DynamicResource TextPrimary}" Margin="0,0,0,12"/>

                                <StackPanel Grid.Row="1">
                                    <RadioButton Name="rbDiagnostico" GroupName="SubModeGroup" Style="{StaticResource CardRadio}" IsChecked="True">
                                        <StackPanel>
                                            <StackPanel Orientation="Horizontal">
                                                <TextBlock Text="Modo Diagn&#x00F3;stico" FontSize="13.5" FontWeight="Bold" Foreground="{DynamicResource TextPrimary}"/>
                                                <Border Background="#243347" CornerRadius="4" Padding="6,1" Margin="8,0,0,0" VerticalAlignment="Center">
                                                    <TextBlock Text="Somente leitura" FontSize="10.5" FontWeight="SemiBold" Foreground="#b5d1f2"/>
                                                </Border>
                                            </StackPanel>
                                            <TextBlock Text="Nada ser&#x00E1; apagado, instalado ou alterado. Ideal para auditoria r&#x00E1;pida e gera&#x00E7;&#x00E3;o de relat&#x00F3;rio."
                                                       Foreground="{DynamicResource TextMuted}" FontSize="11.5" Margin="0,4,0,0" TextWrapping="Wrap"/>
                                        </StackPanel>
                                    </RadioButton>

                                    <RadioButton Name="rbExecucao" GroupName="SubModeGroup" Style="{StaticResource CardRadio}">
                                        <StackPanel>
                                            <StackPanel Orientation="Horizontal">
                                                <TextBlock Text="Modo Execu&#x00E7;&#x00E3;o" FontSize="13.5" FontWeight="Bold" Foreground="{DynamicResource TextPrimary}"/>
                                                <Border Background="#C4613A" CornerRadius="4" Padding="6,1" Margin="8,0,0,0" VerticalAlignment="Center">
                                                    <TextBlock Text="Aplica altera&#x00E7;&#x00F5;es" FontSize="10.5" FontWeight="SemiBold" Foreground="White"/>
                                                </Border>
                                            </StackPanel>
                                            <TextBlock Text="Executa de fato as limpezas, atualiza&#x00E7;&#x00F5;es, otimiza&#x00E7;&#x00F5;es e instala&#x00E7;&#x00F5;es marcadas nas outras abas."
                                                       Foreground="{DynamicResource TextWarning}" FontSize="11.5" Margin="0,4,0,0" TextWrapping="Wrap"/>
                                        </StackPanel>
                                    </RadioButton>
                                </StackPanel>

                                <Border Grid.Row="2" Background="{DynamicResource BgSubCard}" BorderBrush="{DynamicResource BorderSubtle}" BorderThickness="1" CornerRadius="8" Padding="12">
                                    <StackPanel>
                                        <TextBlock Text="SA&#x00CD;DA DE RELAT&#x00D3;RIOS" FontSize="10" FontWeight="Bold" Foreground="{DynamicResource TextMuted}"/>
                                        <TextBlock Name="txtOutputFolderInfo" Text="C:\ProgramData\Preventiva" FontSize="11.5"
                                                   Foreground="{DynamicResource TextSecondary}" Margin="0,3,0,8" TextTrimming="CharacterEllipsis"/>
                                        <StackPanel Orientation="Horizontal">
                                            <Button Name="btnAbrirUltimoRelatorio" Content="Abrir &#x00DA;ltimo Relat&#x00F3;rio" Style="{StaticResource SecondaryButton}" Margin="0,0,8,0"/>
                                            <Button Name="btnAbrirPastaLogs" Content="Abrir Pasta" Style="{StaticResource SecondaryButton}"/>
                                        </StackPanel>
                                    </StackPanel>
                                </Border>
                            </Grid>
                        </Border>
                    </Grid>
                </TabItem>

                <!-- ABA 2: OTIMIZACAO & FERRAMENTAS -->
                <TabItem Header="Otimiza&#x00E7;&#x00E3;o &amp; Ferramentas">
                    <Grid Margin="0,14,0,0">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="1.65*"/>
                            <ColumnDefinition Width="16"/>
                            <ColumnDefinition Width="0.85*"/>
                        </Grid.ColumnDefinitions>

                        <!-- Coluna Esquerda: 16 Tweaks Corporativos Reversiveis -->
                        <Border Grid.Column="0" Background="{DynamicResource BgCard}" BorderBrush="{DynamicResource BorderSubtle}"
                                BorderThickness="1" CornerRadius="10" Padding="15">
                            <Grid>
                                <Grid.RowDefinitions>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="*"/>
                                </Grid.RowDefinitions>

                                <Grid Grid.Row="0" Margin="0,0,0,8">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBlock Text="Tweaks Corporativos (100% Revers&#x00ED;veis)" FontSize="14.5" FontWeight="Bold" Foreground="{DynamicResource TextPrimary}" VerticalAlignment="Center"/>
                                    <TextBlock Name="txtTweaksCount" Grid.Column="1" Text="0 selecionado(s)" FontSize="11.5" FontWeight="SemiBold" Foreground="#C4613A" VerticalAlignment="Center"/>
                                </Grid>

                                <Grid Grid.Row="1" Margin="0,0,0,10">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <StackPanel Grid.Column="0" Orientation="Horizontal">
                                        <Button Name="btnTweakPresetCorp" Content="Corporativo Seguro" Style="{StaticResource PresetButton}"/>
                                        <Button Name="btnTweakPresetClear" Content="Limpar" Style="{StaticResource PresetButton}" Margin="0"/>
                                    </StackPanel>
                                    <StackPanel Grid.Column="1" Orientation="Horizontal">
                                        <Button Name="btnDesfazerTweaks" Content="Desfazer" Style="{StaticResource SecondaryButton}" Padding="11,6" Margin="0,0,6,0"/>
                                        <Button Name="btnAplicarTweaks" Content="Aplicar Tweaks" Style="{StaticResource RunButton}" FontSize="12" Padding="13,6"/>
                                    </StackPanel>
                                </Grid>

                                <!-- 2 Colunas (8 + 8) -->
                                <Grid Grid.Row="2">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="10"/>
                                        <ColumnDefinition Width="*"/>
                                    </Grid.ColumnDefinitions>

                                    <StackPanel Grid.Column="0">
                                        <TextBlock Text="PERFORMANCE &amp; REDE" FontSize="10" FontWeight="Bold" Foreground="{DynamicResource TextMuted}" Margin="2,0,0,5"/>
                                        <CheckBox Name="chkTweakHighPerf" Tag="HighPerformance" Style="{StaticResource TaskCheck}" Content="Plano Energia Alto Desempenho"/>
                                        <CheckBox Name="chkTweakTelemetry" Tag="DisableTelemetry" Style="{StaticResource TaskCheck}" Content="Desativar Telemetria Windows"/>
                                        <CheckBox Name="chkTweakBGApps" Tag="DisableBGApps" Style="{StaticResource TaskCheck}" Content="Desativar Apps em 2&#x00BA; Plano"/>
                                        <CheckBox Name="chkTweakVisualFX" Tag="VisualEffects" Style="{StaticResource TaskCheck}" Content="Efeitos Visuais (Desempenho)"/>
                                        <CheckBox Name="chkTweakDeliveryOpt" Tag="DisableDeliveryOpt" Style="{StaticResource TaskCheck}" Content="Desativar Delivery Opt. (P2P)"/>
                                        <CheckBox Name="chkTweakHibernation" Tag="DisableHibernation" Style="{StaticResource TaskCheck}" Content="Desativar Hiberna&#x00E7;&#x00E3;o (Desktop)"/>
                                        <CheckBox Name="chkTweakLongPaths" Tag="EnableLongPaths" Style="{StaticResource TaskCheck}" Content="Caminhos Longos (&gt;260 chars)"/>
                                        <CheckBox Name="chkTweakEdgeDebloat" Tag="EdgeDebloat" Style="{StaticResource TaskCheck}" Content="Debloat Microsoft Edge (GPO)" Margin="0"/>
                                    </StackPanel>

                                    <StackPanel Grid.Column="2">
                                        <TextBlock Text="PRODUTIVIDADE &amp; WINDOWS LIMPO" FontSize="10" FontWeight="Bold" Foreground="{DynamicResource TextMuted}" Margin="2,0,0,5"/>
                                        <CheckBox Name="chkTweakConsumer" Tag="DisableConsumerFeatures" Style="{StaticResource TaskCheck}" Content="Bloquear Consumer Features"/>
                                        <CheckBox Name="chkTweakBing" Tag="DisableBingSearch" Style="{StaticResource TaskCheck}" Content="Desativar Bing no Menu Iniciar"/>
                                        <CheckBox Name="chkTweakActivity" Tag="DisableActivityHistory" Style="{StaticResource TaskCheck}" Content="Desativar Hist&#x00F3;rico Atividades"/>
                                        <CheckBox Name="chkTweakRightClick" Tag="ClassicRightClick" Style="{StaticResource TaskCheck}" Content="Menu Bot&#x00E3;o Direito Cl&#x00E1;ssico"/>
                                        <CheckBox Name="chkTweakEndTask" Tag="EndTaskTaskbar" Style="{StaticResource TaskCheck}" Content="Finalizar Tarefa na Barra (W11)"/>
                                        <CheckBox Name="chkTweakShowExt" Tag="ShowFileExtensions" Style="{StaticResource TaskCheck}" Content="Mostrar Extens&#x00F5;es de Arquivos"/>
                                        <CheckBox Name="chkTweakWidgets" Tag="DisableWidgets" Style="{StaticResource TaskCheck}" Content="Desativar Widgets (GPO)"/>
                                        <CheckBox Name="chkTweakCopilot" Tag="DisableCopilotAI" Style="{StaticResource TaskCheck}" Content="Desativar Copilot / AI (GPO)" Margin="0"/>
                                    </StackPanel>
                                </Grid>
                            </Grid>
                        </Border>

                        <!-- Coluna Direita: Ferramentas Complementares -->
                        <Border Grid.Column="2" Background="{DynamicResource BgCard}" BorderBrush="{DynamicResource BorderSubtle}"
                                BorderThickness="1" CornerRadius="10" Padding="15">
                            <Grid>
                                <Grid.RowDefinitions>
                                    <RowDefinition Height="*"/>
                                    <RowDefinition Height="Auto"/>
                                </Grid.RowDefinitions>
                                <StackPanel Grid.Row="0">
                                    <TextBlock Text="Perfis P&#x00F3;s-Formata&#x00E7;&#x00E3;o" FontSize="14" FontWeight="Bold" Foreground="{DynamicResource TextPrimary}" Margin="0,0,0,3"/>
                                    <TextBlock Text="Marca Tarefas + Tweaks + Apps em 1 clique."
                                               FontSize="11" Foreground="{DynamicResource TextMuted}" Margin="0,0,0,10" TextWrapping="Wrap"/>
                                    <StackPanel Name="pnlOnboardingProfiles" Margin="0,0,0,14"/>

                                    <TextBlock Text="Ferramentas Complementares" FontSize="14" FontWeight="Bold" Foreground="{DynamicResource TextPrimary}" Margin="0,0,0,8"/>
                                    <Button Name="btnAbrirUtility" Content="Abrir Chris Titus Tech (WinUtil)" Style="{StaticResource SecondaryButton}"
                                            HorizontalAlignment="Stretch" Margin="0,0,0,8" Padding="12,9"/>
                                    <Button Name="btnAgendarSemanal" Content="Agendamento Semanal (Sex 18h)" Style="{StaticResource SecondaryButton}"
                                            HorizontalAlignment="Stretch" Margin="0,0,0,8" Padding="12,9"/>
                                    <Button Name="btnAbrirConfig" Content="Editar settings.json" Style="{StaticResource SecondaryButton}"
                                            HorizontalAlignment="Stretch" Padding="12,9"/>
                                </StackPanel>

                                <Border Grid.Row="1" Background="{DynamicResource BgSubCard}" BorderBrush="{DynamicResource BorderSubtle}" BorderThickness="1" CornerRadius="8" Padding="12">
                                    <StackPanel>
                                        <TextBlock Text="SEGURAN&#x00C7;A CORPORATIVA" FontSize="10" FontWeight="Bold" Foreground="{DynamicResource TextGood}"/>
                                        <TextBlock Text="Todos os tweaks ao lado usam chaves validadas/GPOs e podem ser revertidos pelo bot&#x00E3;o Desfazer."
                                                   FontSize="11" Foreground="{DynamicResource TextMuted}" Margin="0,4,0,0" TextWrapping="Wrap"/>
                                    </StackPanel>
                                </Border>
                            </Grid>
                        </Border>
                    </Grid>
                </TabItem>

                <!-- ABA 3: SOFTWARES (WINGET) -->
                <TabItem Header="Softwares (Winget)">
                    <Border Margin="0,14,0,0" Background="{DynamicResource BgCard}" BorderBrush="{DynamicResource BorderSubtle}"
                            BorderThickness="1" CornerRadius="10" Padding="16">
                        <Grid>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="*"/>
                            </Grid.RowDefinitions>

                            <Grid Grid.Row="0" Margin="0,0,0,14">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <StackPanel>
                                    <TextBlock Text="Instala&#x00E7;&#x00E3;o Autom&#x00E1;tica via Winget" FontSize="14.5" FontWeight="Bold" Foreground="{DynamicResource TextPrimary}"/>
                                    <TextBlock Name="txtSoftwaresCount" Text="0 software(s) selecionado(s)"
                                               FontSize="11.5" Foreground="{DynamicResource TextMuted}" Margin="0,2,0,0"/>
                                </StackPanel>
                                <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                                    <Button Name="btnSelectAllSoft" Content="Selecionar Todos" Style="{StaticResource SecondaryButton}" Margin="0,0,8,0"/>
                                    <Button Name="btnClearSoft" Content="Limpar Sele&#x00E7;&#x00E3;o" Style="{StaticResource SecondaryButton}" Margin="0,0,8,0"/>
                                    <Button Name="btnUpgradeAllSoft" Content="Atualizar Todos" Style="{StaticResource SecondaryButton}" Margin="0,0,8,0" ToolTip="Executa winget upgrade --all silenciosamente"/>
                                    <Button Name="btnInstalarSoftwares" Content="Instalar Selecionados" Style="{StaticResource RunButton}" FontSize="12.5" Padding="14,8"/>
                                </StackPanel>
                            </Grid>

                            <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
                                <UniformGrid Name="pnlSoftwares" Columns="2" VerticalAlignment="Top"/>
                            </ScrollViewer>
                        </Grid>
                    </Border>
                </TabItem>
                <!-- ABA 4: REDE & SUPORTE RAPIDO -->
                <TabItem Name="tabRede" Header="Rede &amp; Suporte">
                    <Grid Margin="0,14,0,0">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="1.15*"/>
                            <ColumnDefinition Width="16"/>
                            <ColumnDefinition Width="0.85*"/>
                        </Grid.ColumnDefinitions>

                        <!-- Esquerda: Info de Rede + Troca de DNS -->
                        <Border Grid.Column="0" Background="{DynamicResource BgCard}" BorderBrush="{DynamicResource BorderSubtle}"
                                BorderThickness="1" CornerRadius="10" Padding="16">
                            <Grid>
                                <Grid.RowDefinitions>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="*"/>
                                    <RowDefinition Height="Auto"/>
                                </Grid.RowDefinitions>

                                <Grid Grid.Row="0" Margin="0,0,0,12">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <StackPanel>
                                        <TextBlock Text="Diagn&#x00F3;stico de Rede ao Vivo" FontSize="14.5" FontWeight="Bold" Foreground="{DynamicResource TextPrimary}"/>
                                        <TextBlock Text="Informa&#x00E7;&#x00F5;es do adaptador principal e conectividade." FontSize="11.5" Foreground="{DynamicResource TextMuted}"/>
                                    </StackPanel>
                                    <Button Name="btnRefreshNet" Grid.Column="1" Content="Atualizar Info" Style="{StaticResource SecondaryButton}" VerticalAlignment="Center"/>
                                </Grid>

                                <Border Grid.Row="1" Background="{DynamicResource BgSubCard}" BorderBrush="{DynamicResource BorderSubtle}" BorderThickness="1" CornerRadius="8" Padding="14,10" Margin="0,0,0,14">
                                    <Grid>
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="135"/>
                                            <ColumnDefinition Width="*"/>
                                        </Grid.ColumnDefinitions>
                                        <Grid.RowDefinitions>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="Auto"/>
                                        </Grid.RowDefinitions>

                                        <TextBlock Grid.Row="0" Grid.Column="0" Text="Adaptador:" FontSize="12" FontWeight="SemiBold" Foreground="{DynamicResource TextMuted}" Margin="0,4"/>
                                        <TextBlock Name="txtNetAdapter" Grid.Row="0" Grid.Column="1" Text="Clique em Atualizar Info" FontSize="12" FontWeight="SemiBold" Foreground="{DynamicResource TextPrimary}" Margin="0,4" TextTrimming="CharacterEllipsis"/>

                                        <TextBlock Grid.Row="1" Grid.Column="0" Text="IP Local (IPv4):" FontSize="12" FontWeight="SemiBold" Foreground="{DynamicResource TextMuted}" Margin="0,4"/>
                                        <TextBlock Name="txtNetLocalIP" Grid.Row="1" Grid.Column="1" Text="-" FontSize="12" FontWeight="SemiBold" Foreground="{DynamicResource TextPrimary}" Margin="0,4"/>

                                        <TextBlock Grid.Row="2" Grid.Column="0" Text="Gateway:" FontSize="12" FontWeight="SemiBold" Foreground="{DynamicResource TextMuted}" Margin="0,4"/>
                                        <TextBlock Name="txtNetGateway" Grid.Row="2" Grid.Column="1" Text="-" FontSize="12" FontWeight="SemiBold" Foreground="{DynamicResource TextPrimary}" Margin="0,4"/>

                                        <TextBlock Grid.Row="3" Grid.Column="0" Text="DNS Atual:" FontSize="12" FontWeight="SemiBold" Foreground="{DynamicResource TextMuted}" Margin="0,4"/>
                                        <TextBlock Name="txtNetDns" Grid.Row="3" Grid.Column="1" Text="-" FontSize="12" FontWeight="SemiBold" Foreground="{DynamicResource TextPrimary}" Margin="0,4" TextTrimming="CharacterEllipsis"/>

                                        <TextBlock Grid.Row="4" Grid.Column="0" Text="Endere&#x00E7;o MAC:" FontSize="12" FontWeight="SemiBold" Foreground="{DynamicResource TextMuted}" Margin="0,4"/>
                                        <TextBlock Name="txtNetMac" Grid.Row="4" Grid.Column="1" Text="-" FontSize="12" FontWeight="SemiBold" Foreground="{DynamicResource TextPrimary}" Margin="0,4"/>

                                        <TextBlock Grid.Row="5" Grid.Column="0" Text="IP P&#x00FA;blico:" FontSize="12" FontWeight="SemiBold" Foreground="{DynamicResource TextMuted}" Margin="0,4"/>
                                        <TextBlock Name="txtNetPublicIP" Grid.Row="5" Grid.Column="1" Text="-" FontSize="12" FontWeight="SemiBold" Foreground="{DynamicResource TextPrimary}" Margin="0,4"/>

                                        <TextBlock Grid.Row="6" Grid.Column="0" Text="Lat&#x00EA;ncia (8.8.8.8):" FontSize="12" FontWeight="SemiBold" Foreground="{DynamicResource TextMuted}" Margin="0,4"/>
                                        <TextBlock Name="txtNetLatency" Grid.Row="6" Grid.Column="1" Text="-" FontSize="12" FontWeight="Bold" Foreground="{DynamicResource TextGood}" Margin="0,4"/>
                                    </Grid>
                                </Border>

                                <StackPanel Grid.Row="2">
                                    <TextBlock Text="TROCAR DNS EM 1 CLIQUE" FontSize="10" FontWeight="Bold" Foreground="{DynamicResource TextMuted}" Margin="0,0,0,8"/>
                                    <UniformGrid Columns="4">
                                        <Button Name="btnDnsCloudflare" Content="Cloudflare 1.1.1.1" Style="{StaticResource SecondaryButton}" FontSize="11.5" Padding="6,8" Margin="0,0,6,0"/>
                                        <Button Name="btnDnsGoogle" Content="Google 8.8.8.8" Style="{StaticResource SecondaryButton}" FontSize="11.5" Padding="6,8" Margin="0,0,6,0"/>
                                        <Button Name="btnDnsQuad9" Content="Quad9 9.9.9.9" Style="{StaticResource SecondaryButton}" FontSize="11.5" Padding="6,8" Margin="0,0,6,0"/>
                                        <Button Name="btnDnsDhcp" Content="Auto (DHCP)" Style="{StaticResource SecondaryButton}" FontSize="11.5" Padding="6,8"/>
                                    </UniformGrid>
                                </StackPanel>
                            </Grid>
                        </Border>

                        <!-- Direita: Acoes Rapidas de Suporte -->
                        <Border Grid.Column="2" Background="{DynamicResource BgCard}" BorderBrush="{DynamicResource BorderSubtle}"
                                BorderThickness="1" CornerRadius="10" Padding="16">
                            <Grid>
                                <Grid.RowDefinitions>
                                    <RowDefinition Height="*"/>
                                    <RowDefinition Height="Auto"/>
                                </Grid.RowDefinitions>
                                <StackPanel Grid.Row="0">
                                    <TextBlock Text="A&#x00E7;&#x00F5;es R&#x00E1;pidas de Suporte" FontSize="14.5" FontWeight="Bold" Foreground="{DynamicResource TextPrimary}" Margin="0,0,0,4"/>
                                    <TextBlock Text="Comandos imediatos sem precisar abrir o CMD." FontSize="11.5" Foreground="{DynamicResource TextMuted}" Margin="0,0,0,14"/>

                                    <Button Name="btnQuickFlushDns" Content="Flush DNS Imediato" Style="{StaticResource SecondaryButton}" HorizontalAlignment="Stretch" Margin="0,0,0,9" Padding="12,10"/>
                                    <Button Name="btnQuickRenewIp" Content="Renovar IP (Release + Renew)" Style="{StaticResource SecondaryButton}" HorizontalAlignment="Stretch" Margin="0,0,0,9" Padding="12,10"/>
                                    <Button Name="btnQuickSpooler" Content="Reiniciar Spooler + Limpar Fila Impress&#x00E3;o" Style="{StaticResource SecondaryButton}" HorizontalAlignment="Stretch" Margin="0,0,0,9" Padding="12,10"/>
                                    <Button Name="btnQuickNcpa" Content="Abrir Conex&#x00F5;es de Rede (ncpa.cpl)" Style="{StaticResource SecondaryButton}" HorizontalAlignment="Stretch" Margin="0,0,0,9" Padding="12,10"/>
                                    <Button Name="btnQuickDevMgmt" Content="Abrir Gerenciador de Dispositivos" Style="{StaticResource SecondaryButton}" HorizontalAlignment="Stretch" Padding="12,10"/>
                                </StackPanel>

                                <Border Grid.Row="1" Background="{DynamicResource BgSubCard}" BorderBrush="{DynamicResource BorderSubtle}" BorderThickness="1" CornerRadius="8" Padding="12">
                                    <StackPanel>
                                        <TextBlock Text="RETORNO DA A&#x00C7;&#x00C3;O" FontSize="10" FontWeight="Bold" Foreground="{DynamicResource TextMuted}"/>
                                        <TextBlock Name="txtNetActionResult" Text="Pronto para diagn&#x00F3;stico." FontSize="11.5" Foreground="{DynamicResource TextGood}" Margin="0,4,0,0" TextWrapping="Wrap"/>
                                    </StackPanel>
                                </Border>
                            </Grid>
                        </Border>
                    </Grid>
                </TabItem>
            </TabControl>

            <!-- Rodape / Barra de Acao e Progresso -->
            <Border Grid.Row="3" Background="{DynamicResource BgFooter}" BorderBrush="{DynamicResource BorderSubtle}" BorderThickness="0,1,0,0"
                    CornerRadius="0,0,12,12" Padding="24,14">
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>

                    <StackPanel Grid.Column="0" VerticalAlignment="Center" Margin="0,0,18,0">
                        <TextBlock Name="txtResumoSelecao" Text="Resumo: Light &#x2022; Diagn&#x00F3;stico" FontSize="12"
                                   FontWeight="SemiBold" Foreground="{DynamicResource TextSecondary}"/>
                        <TextBlock Name="txtStatus" Text="Pronto para iniciar." FontSize="11.5"
                                   Foreground="{DynamicResource TextMuted}" Margin="0,2,0,0"/>
                        <ProgressBar Name="pbProgresso" Height="5" Margin="0,8,0,0" Visibility="Collapsed"
                                     IsIndeterminate="True" Background="{DynamicResource BgTab}" Foreground="#C4613A" BorderThickness="0"/>
                    </StackPanel>

                    <Button Name="btnExecutar" Grid.Column="1" Content="INICIAR PREVENTIVA" Width="220" Height="44"
                            Style="{StaticResource RunButton}"/>
                </Grid>
            </Border>
        </Grid>
    </Border>
</Window>
"@

$reader = (New-Object System.Xml.XmlNodeReader $XAML)
try {
    $Window = [Windows.Markup.XamlReader]::Load($reader)
} catch {
    Write-Host "Falha ao carregar XAML da interface." -ForegroundColor Red
    Write-Host $_.Exception.Message
    Read-Host "Pressione ENTER para sair"
    exit
}

# Bind de controles
$TitleBar                = $Window.FindName("TitleBar")
$btnThemeToggle          = $Window.FindName("btnThemeToggle")
$txtThemeIcon            = $Window.FindName("txtThemeIcon")
$txtThemeLabel           = $Window.FindName("txtThemeLabel")
$btnMinimize             = $Window.FindName("btnMinimize")
$btnClose                = $Window.FindName("btnClose")
$imgLogo                 = $Window.FindName("imgLogo")
$linkSite                = $Window.FindName("linkSite")
$txtHostName             = $Window.FindName("txtHostName")
$txtFreeSpace            = $Window.FindName("txtFreeSpace")
$txtAdmin                = $Window.FindName("txtAdmin")
$bdAdmin                 = $Window.FindName("bdAdmin")
$txtTasksCount           = $Window.FindName("txtTasksCount")
$btnPresetLight          = $Window.FindName("btnPresetLight")
$btnPresetModerate       = $Window.FindName("btnPresetModerate")
$btnPresetHeavy          = $Window.FindName("btnPresetHeavy")
$btnPresetRecovery       = $Window.FindName("btnPresetRecovery")
$btnPresetClear          = $Window.FindName("btnPresetClear")
$rbDiagnostico           = $Window.FindName("rbDiagnostico")
$rbExecucao              = $Window.FindName("rbExecucao")
$txtOutputFolderInfo     = $Window.FindName("txtOutputFolderInfo")
$btnAbrirUltimoRelatorio = $Window.FindName("btnAbrirUltimoRelatorio")
$btnAbrirPastaLogs       = $Window.FindName("btnAbrirPastaLogs")
$txtTweaksCount          = $Window.FindName("txtTweaksCount")
$btnTweakPresetCorp      = $Window.FindName("btnTweakPresetCorp")
$btnTweakPresetClear     = $Window.FindName("btnTweakPresetClear")
$btnAplicarTweaks        = $Window.FindName("btnAplicarTweaks")
$btnDesfazerTweaks       = $Window.FindName("btnDesfazerTweaks")
$btnAbrirUtility         = $Window.FindName("btnAbrirUtility")
$btnAgendarSemanal       = $Window.FindName("btnAgendarSemanal")
$btnAbrirConfig          = $Window.FindName("btnAbrirConfig")
$pnlSoftwares            = $Window.FindName("pnlSoftwares")
$txtSoftwaresCount       = $Window.FindName("txtSoftwaresCount")
$btnSelectAllSoft        = $Window.FindName("btnSelectAllSoft")
$btnClearSoft            = $Window.FindName("btnClearSoft")
$pnlOnboardingProfiles   = $Window.FindName("pnlOnboardingProfiles")
$btnUpgradeAllSoft       = $Window.FindName("btnUpgradeAllSoft")
$btnRefreshNet           = $Window.FindName("btnRefreshNet")
$txtNetAdapter           = $Window.FindName("txtNetAdapter")
$txtNetLocalIP           = $Window.FindName("txtNetLocalIP")
$txtNetGateway           = $Window.FindName("txtNetGateway")
$txtNetDns               = $Window.FindName("txtNetDns")
$txtNetMac               = $Window.FindName("txtNetMac")
$txtNetPublicIP          = $Window.FindName("txtNetPublicIP")
$txtNetLatency           = $Window.FindName("txtNetLatency")
$btnDnsCloudflare        = $Window.FindName("btnDnsCloudflare")
$btnDnsGoogle            = $Window.FindName("btnDnsGoogle")
$btnDnsQuad9             = $Window.FindName("btnDnsQuad9")
$btnDnsDhcp              = $Window.FindName("btnDnsDhcp")
$btnQuickFlushDns        = $Window.FindName("btnQuickFlushDns")
$btnQuickRenewIp         = $Window.FindName("btnQuickRenewIp")
$btnQuickSpooler         = $Window.FindName("btnQuickSpooler")
$btnQuickNcpa            = $Window.FindName("btnQuickNcpa")
$btnQuickDevMgmt         = $Window.FindName("btnQuickDevMgmt")
$txtNetActionResult      = $Window.FindName("txtNetActionResult")
$btnInstalarSoftwares    = $Window.FindName("btnInstalarSoftwares")
$txtResumoSelecao        = $Window.FindName("txtResumoSelecao")
$txtStatus               = $Window.FindName("txtStatus")
$pbProgresso             = $Window.FindName("pbProgresso")
$btnExecutar             = $Window.FindName("btnExecutar")

$BrushConv = [System.Windows.Media.BrushConverter]::new()

# ============================================
# SISTEMA DE TEMAS (Auto / Claro / Escuro)
# ============================================
$ThemePalettes = @{
    "Dark" = @{
        BgWindow              = "#141419"
        BgHeader              = "#101015"
        BgCard                = "#1d1e26"
        BgSubCard             = "#161821"
        BgFooter              = "#191b24"
        BgControl             = "#171820"
        BgControlHover        = "#222430"
        BgControlSelected     = "#242026"
        BgControlCheckedGreen = "#1d2824"
        BgSecondaryBtn        = "#242736"
        BgSecondaryBtnHover   = "#30354a"
        BgTab                 = "#1b1d26"
        BgTabHover            = "#252836"
        BgPill                = "#1d1f2a"
        BgTitleHover          = "#2a2c38"
        BgBadgeAdmin          = "#1d2a23"
        BorderWindow          = "#2f3242"
        BorderSubtle          = "#2b2d3a"
        BorderControl         = "#2b2e3d"
        BorderControlHover    = "#484d66"
        BorderBadgeAdmin      = "#2f523e"
        TextPrimary           = "#f0f0f5"
        TextSecondary         = "#c9cde0"
        TextMuted             = "#8f93a8"
        TextWarning           = "#d99a7c"
        TextGood              = "#7ad19f"
        ScrollThumb           = "#383c52"
    }
    "Light" = @{
        BgWindow              = "#f4f5f8"
        BgHeader              = "#ffffff"
        BgCard                = "#ffffff"
        BgSubCard             = "#f7f8fc"
        BgFooter              = "#ffffff"
        BgControl             = "#f8f9fc"
        BgControlHover        = "#eef0f7"
        BgControlSelected     = "#fdf3ee"
        BgControlCheckedGreen = "#edf7f1"
        BgSecondaryBtn        = "#eef0f6"
        BgSecondaryBtnHover   = "#e2e6f0"
        BgTab                 = "#e7eaf2"
        BgTabHover            = "#dce0eb"
        BgPill                = "#f0f2f7"
        BgTitleHover          = "#e6e9f2"
        BgBadgeAdmin          = "#e8f6ee"
        BorderWindow          = "#cfd4e2"
        BorderSubtle          = "#e1e4ee"
        BorderControl         = "#d5dae6"
        BorderControlHover    = "#b3bad0"
        BorderBadgeAdmin      = "#9ed4b6"
        TextPrimary           = "#1a1d26"
        TextSecondary         = "#3c4257"
        TextMuted             = "#646b82"
        TextWarning           = "#a84a24"
        TextGood              = "#236b43"
        ScrollThumb           = "#bfc5d6"
    }
}

$ThemePrefFile = Join-Path $BaseDir "Config\theme.pref"
$script:ThemeMode = "Auto"
if (Test-Path -LiteralPath $ThemePrefFile) {
    $saved = (Get-Content -LiteralPath $ThemePrefFile -ErrorAction SilentlyContinue | Select-Object -First 1)
    if ($saved -in @("Auto", "Claro", "Escuro")) { $script:ThemeMode = $saved }
}

function Get-WindowsIsLightTheme {
    try {
        $v = (Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -ErrorAction Stop).AppsUseLightTheme
        return ($v -eq 1)
    } catch { return $false }
}

$ApplyTheme = {
    param([string]$ModeName)
    $script:ThemeMode = $ModeName
    try { Set-Content -LiteralPath $ThemePrefFile -Value $ModeName -Encoding ASCII -ErrorAction SilentlyContinue } catch {}

    $effective = "Dark"
    if ($ModeName -eq "Claro") { $effective = "Light" }
    elseif ($ModeName -eq "Escuro") { $effective = "Dark" }
    else { $effective = if (Get-WindowsIsLightTheme) { "Light" } else { "Dark" } }

    $pal = $ThemePalettes[$effective]
    foreach ($k in $pal.Keys) {
        $Window.Resources[$k] = $BrushConv.ConvertFromString($pal[$k])
    }

    if ($ModeName -eq "Auto") {
        $txtThemeLabel.Text = "Auto"
        $txtThemeIcon.Text = [string][char]0x25D0
        $txtThemeIcon.Foreground = $BrushConv.ConvertFromString($(if ($effective -eq "Light") { "#3D5270" } else { "#c9cde0" }))
    } elseif ($ModeName -eq "Claro") {
        $txtThemeLabel.Text = "Claro"
        $txtThemeIcon.Text = [string][char]0x2600
        $txtThemeIcon.Foreground = $BrushConv.ConvertFromString("#e68a00")
    } else {
        $txtThemeLabel.Text = "Escuro"
        $txtThemeIcon.Text = [string][char]0x263E
        $txtThemeIcon.Foreground = $BrushConv.ConvertFromString("#5b9dff")
    }

    if ($HighlightActivePreset) { & $HighlightActivePreset }
}

$btnThemeToggle.Add_Click({
    $next = switch ($script:ThemeMode) {
        "Auto"   { "Claro" }
        "Claro"  { "Escuro" }
        default  { "Auto" }
    }
    & $ApplyTheme $next
})

# ============================================
# CONTROLES DE TAREFAS, TWEAKS E SOFTWARES
# ============================================
$TaskCheckboxNames = @(
    "chkTaskInventory", "chkTaskDiskEvents", "chkTaskCriticalServices", "chkTaskCleanTemp",
    "chkTaskEmptyRecycleBin", "chkTaskFlushDns", "chkTaskFolderScan", "chkTaskSecurityAudit",
    "chkTaskWindowsUpdate", "chkTaskDefenderScan", "chkTaskTrim", "chkTaskIntegrity",
    "chkTaskWinSxS", "chkTaskFullFileScan", "chkTaskRestorePoint", "chkTaskRecovery"
)
$TaskCheckboxes = @($TaskCheckboxNames | ForEach-Object { $Window.FindName($_) })

$Presets = @{
    "Light"    = @("Inventory", "DiskEvents", "CriticalServices", "CleanTemp", "EmptyRecycleBin", "FlushDns", "FolderScan", "SecurityAudit")
    "Moderate" = @("Inventory", "DiskEvents", "CriticalServices", "CleanTemp", "EmptyRecycleBin", "FlushDns", "FolderScan", "SecurityAudit", "WindowsUpdate", "DefenderScan", "Trim")
    "Heavy"    = @("Inventory", "DiskEvents", "CriticalServices", "CleanTemp", "EmptyRecycleBin", "FlushDns", "FolderScan", "SecurityAudit", "WindowsUpdate", "DefenderScan", "Trim", "Integrity", "WinSxS", "FullFileScan", "RestorePoint")
    "Recovery" = @("Inventory", "DiskEvents", "CriticalServices", "CleanTemp", "EmptyRecycleBin", "FlushDns", "FolderScan", "SecurityAudit", "WindowsUpdate", "DefenderScan", "Trim", "Integrity", "WinSxS", "FullFileScan", "RestorePoint", "Recovery")
}
$script:ActivePresetName = "Light"
$script:IsApplyingPreset = $false

$TweakCheckboxNames = @(
    "chkTweakHighPerf", "chkTweakTelemetry", "chkTweakBGApps", "chkTweakVisualFX",
    "chkTweakDeliveryOpt", "chkTweakHibernation", "chkTweakLongPaths", "chkTweakEdgeDebloat",
    "chkTweakConsumer", "chkTweakBing", "chkTweakActivity", "chkTweakRightClick",
    "chkTweakEndTask", "chkTweakShowExt", "chkTweakWidgets", "chkTweakCopilot"
)
$TweakCheckboxes = @($TweakCheckboxNames | ForEach-Object { $Window.FindName($_) })
$CorpSafeTweaks = @(
    "DisableTelemetry", "DisableBGApps", "DisableDeliveryOpt", "EnableLongPaths",
    "EdgeDebloat", "DisableConsumerFeatures", "DisableBingSearch", "DisableActivityHistory",
    "EndTaskTaskbar", "ShowFileExtensions", "DisableWidgets", "DisableCopilotAI"
)

# Preencher informacoes da maquina
$txtHostName.Text = $HostName
$txtFreeSpace.Text = "$FreeGB GB"
$txtOutputFolderInfo.Text = $OutputFolder
if ($IsAdmin) {
    $txtAdmin.Text = "Administrador"
} else {
    $txtAdmin.Text = "Padr$([char]0x00E3)o"
    $txtAdmin.Foreground = $BrushConv.ConvertFromString("#C4613A")
}

# Arrastar janela e botoes de titulo
$TitleBar.Add_MouseLeftButtonDown({
    if ($_.ChangedButton -eq [System.Windows.Input.MouseButton]::Left) {
        $Window.DragMove()
    }
})
$btnMinimize.Add_Click({ $Window.WindowState = "Minimized" })
$btnClose.Add_Click({ $Window.Close() })

# Logo
$LogoPath = Join-Path $BaseDir "Assets\logo.png"
if (Test-Path -LiteralPath $LogoPath) {
    try {
        $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
        $bitmap.BeginInit()
        $bitmap.UriSource = [System.Uri]::new($LogoPath)
        $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bitmap.EndInit()
        $imgLogo.Source = $bitmap
    } catch {}
}

if ($linkSite) {
    $linkSite.Add_Click({ Start-Process "https://techfontes.com.br" })
}

$PresetButtons = @{
    "Light"    = $btnPresetLight
    "Moderate" = $btnPresetModerate
    "Heavy"    = $btnPresetHeavy
    "Recovery" = $btnPresetRecovery
}

$HighlightActivePreset = {
    foreach ($kv in $PresetButtons.GetEnumerator()) {
        if ($kv.Key -eq $script:ActivePresetName) {
            $kv.Value.Background = $BrushConv.ConvertFromString("#C4613A")
            $kv.Value.BorderBrush = $BrushConv.ConvertFromString("#d97248")
            $kv.Value.Foreground = [System.Windows.Media.Brushes]::White
        } else {
            $kv.Value.Background = $Window.Resources["BgSecondaryBtn"]
            $kv.Value.BorderBrush = $Window.Resources["BorderControl"]
            $kv.Value.Foreground = $Window.Resources["TextSecondary"]
        }
    }
}

$DynamicCheckboxes = @()
$UpdateSummary = {
    $selectedTasks = @($TaskCheckboxes | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
    $taskCount = $selectedTasks.Count
    $txtTasksCount.Text = "$taskCount selecionada(s)"

    if (-not $script:IsApplyingPreset) {
        $matched = "Personalizado"
        foreach ($pName in @("Light", "Moderate", "Heavy", "Recovery")) {
            $pTasks = $Presets[$pName]
            if ($taskCount -eq $pTasks.Count -and (@($selectedTasks | Where-Object { $pTasks -notcontains $_ }).Count -eq 0)) {
                $matched = $pName
                break
            }
        }
        $script:ActivePresetName = $matched
    }
    & $HighlightActivePreset

    $subText = if ($rbExecucao.IsChecked) { "Execu$([char]0x00E7)$([char]0x00E3)o" } else { "Diagn$([char]0x00F3)stico" }
    $softCount = @($DynamicCheckboxes | Where-Object { $_.IsChecked }).Count
    $txtSoftwaresCount.Text = "$softCount software(s) selecionado(s) $([char]0x2014) clique em 'Instalar Selecionados' para instalar agora"

    $extras = @()
    $tweakCount = @($TweakCheckboxes | Where-Object { $_.IsChecked }).Count
    if ($txtTweaksCount) { $txtTweaksCount.Text = "$tweakCount selecionado(s)" }
    if ($rbExecucao.IsChecked -and $tweakCount -gt 0) { $extras += "$tweakCount tweak(s)" }
    if ($rbExecucao.IsChecked -and $softCount -gt 0) { $extras += "$softCount app(s) Winget" }

    $resumo = "Selecionado: $($script:ActivePresetName) ($taskCount tarefas)  $([char]0x2022)  $subText"
    if ($extras.Count -gt 0) { $resumo += "  $([char]0x2022)  " + ($extras -join " + ") }
    $txtResumoSelecao.Text = $resumo
}

$ApplyPreset = {
    param([string]$PresetName)
    $script:IsApplyingPreset = $true
    $targetTasks = if ($Presets.ContainsKey($PresetName)) { $Presets[$PresetName] } else { @() }
    foreach ($cb in $TaskCheckboxes) {
        $cb.IsChecked = ($targetTasks -contains $cb.Tag)
    }
    $script:ActivePresetName = if ($targetTasks.Count -gt 0) { $PresetName } else { "Personalizado" }
    $script:IsApplyingPreset = $false
    & $UpdateSummary
}

$btnPresetLight.Add_Click({ # Popular Perfis Pos-Formatacao (settings.json)
$SecondaryBtnStyle = $Window.FindResource("SecondaryButton")
if ($Config -and $Config.OnboardingProfiles -and $pnlOnboardingProfiles) {
    foreach ($prof in $Config.OnboardingProfiles) {
        $btnP = New-Object System.Windows.Controls.Button
        $btnP.Style = $SecondaryBtnStyle
        $btnP.Content = "Perfil: $($prof.Name)"
        $btnP.ToolTip = $prof.Description
        $btnP.HorizontalAlignment = "Stretch"
        $btnP.Margin = New-Object System.Windows.Thickness(0, 0, 0, 7)
        $btnP.Padding = New-Object System.Windows.Thickness(12, 9, 12, 9)
        $btnP.Tag = $prof
        $btnP.Add_Click({
            $p = $this.Tag
            if ($p.Preset) { & $ApplyPreset $p.Preset }
            foreach ($tcb in $TweakCheckboxes) {
                $tcb.IsChecked = ($p.Tweaks -contains $tcb.Tag)
            }
            foreach ($scb in $DynamicCheckboxes) {
                $scb.IsChecked = ($p.Softwares -contains $scb.Tag)
            }
            $rbExecucao.IsChecked = $true
            & $UpdateSummary
            $txtStatus.Text = "Perfil '$($p.Name)' carregado! Clique em INICIAR PREVENTIVA para aplicar."
        })
        $pnlOnboardingProfiles.Children.Add($btnP) | Out-Null
    }
}

# Botao Atualizar Todos os Apps (winget upgrade --all)
if ($btnUpgradeAllSoft) {
    $btnUpgradeAllSoft.Add_Click({
        $ScriptFile = Join-Path $BaseDir "Invoke-Preventiva.ps1"
        if (-not (Test-Path -LiteralPath $ScriptFile)) { return }
        $ArgsList = @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$ScriptFile`"",
            "-Mode", "`"WingetUpgrade`"", "-SubModo", "`"Execucao`"",
            "-Tasks", "`"None`"", "-UpgradeAllSoftware"
        )
        try {
            $btnExecutar.IsEnabled = $false
            $btnInstalarSoftwares.IsEnabled = $false
            $btnUpgradeAllSoft.IsEnabled = $false
            $btnAplicarTweaks.IsEnabled = $false
            $btnDesfazerTweaks.IsEnabled = $false
            $btnExecutar.Content = "ATUALIZANDO..."
            $pbProgresso.Visibility = "Visible"
            $txtStatus.Text = "Atualizando todos os apps instalados via Winget... Acompanhe no console."
            $script:StartTime = Get-Date
            $script:CurrentProcess = Start-Process powershell -ArgumentList ($ArgsList -join " ") -WindowStyle Normal -PassThru
            $script:PollTimer.Start()
        } catch {
            $btnExecutar.IsEnabled = $true
            $btnInstalarSoftwares.IsEnabled = $true
        if ($btnUpgradeAllSoft) { $btnUpgradeAllSoft.IsEnabled = $true }
            $btnUpgradeAllSoft.IsEnabled = $true
            $btnAplicarTweaks.IsEnabled = $true
            $btnDesfazerTweaks.IsEnabled = $true
            $btnExecutar.Content = "INICIAR PREVENTIVA"
            $pbProgresso.Visibility = "Collapsed"
            $txtStatus.Text = "Erro ao iniciar atualiza$([char]0x00E7)$([char]0x00E3)o Winget: $_"
        }
    })
}

# Aba Rede & Suporte Rapido
$RefreshNetworkUI = {
    try {
        if (Get-Command Get-PreventivaNetworkSummary -ErrorAction SilentlyContinue) {
            $info = Get-PreventivaNetworkSummary
            $txtNetAdapter.Text  = $info.Adapter
            $txtNetLocalIP.Text  = $info.LocalIP
            $txtNetGateway.Text  = $info.Gateway
            $txtNetDns.Text      = $info.DnsList
            $txtNetMac.Text      = $info.Mac
            $txtNetPublicIP.Text = $info.PublicIP
            $txtNetLatency.Text  = $info.Latency
            $txtNetActionResult.Text = "Informa$([char]0x00E7)$([char]0x00F5)es de rede atualizadas ($(Get-Date -Format 'HH:mm:ss'))."
        }
    } catch {
        $txtNetActionResult.Text = "Falha ao ler rede: $_"
    }
}

$btnRefreshNet.Add_Click($RefreshNetworkUI)
$btnDnsCloudflare.Add_Click({
    try { $txtNetActionResult.Text = (Set-PreventivaDns -Provider "Cloudflare"); & $RefreshNetworkUI } catch { $txtNetActionResult.Text = "Erro: $_" }
})
$btnDnsGoogle.Add_Click({
    try { $txtNetActionResult.Text = (Set-PreventivaDns -Provider "Google"); & $RefreshNetworkUI } catch { $txtNetActionResult.Text = "Erro: $_" }
})
$btnDnsQuad9.Add_Click({
    try { $txtNetActionResult.Text = (Set-PreventivaDns -Provider "Quad9"); & $RefreshNetworkUI } catch { $txtNetActionResult.Text = "Erro: $_" }
})
$btnDnsDhcp.Add_Click({
    try { $txtNetActionResult.Text = (Set-PreventivaDns -Provider "DHCP"); & $RefreshNetworkUI } catch { $txtNetActionResult.Text = "Erro: $_" }
})
$btnQuickFlushDns.Add_Click({
    try { ipconfig /flushdns | Out-Null; $txtNetActionResult.Text = "Flush DNS executado com sucesso ($(Get-Date -Format 'HH:mm:ss'))." } catch { $txtNetActionResult.Text = "Erro: $_" }
})
$btnQuickRenewIp.Add_Click({
    try { $txtNetActionResult.Text = (Invoke-PreventivaRenewIp); & $RefreshNetworkUI } catch { $txtNetActionResult.Text = "Erro: $_" }
})
$btnQuickSpooler.Add_Click({
    try { $txtNetActionResult.Text = (Restart-PreventivaPrintSpooler) } catch { $txtNetActionResult.Text = "Erro: $_" }
})
$btnQuickNcpa.Add_Click({ Start-Process "ncpa.cpl" })
$btnQuickDevMgmt.Add_Click({ Start-Process "devmgmt.msc" })

& $ApplyPreset "Light" })
$btnPresetModerate.Add_Click({ & $ApplyPreset "Moderate" })
$btnPresetHeavy.Add_Click({ & $ApplyPreset "Heavy" })
$btnPresetRecovery.Add_Click({ & $ApplyPreset "Recovery" })
$btnPresetClear.Add_Click({ & $ApplyPreset "None" })

foreach ($cb in $TaskCheckboxes) {
    $cb.Add_Checked($UpdateSummary)
    $cb.Add_Unchecked($UpdateSummary)
}

# Popular lista de softwares em Cards (com DynamicResource para suportar Claro/Escuro)
$CardCheckStyle = $Window.FindResource("CardCheck")
if ($Config -and $Config.SoftwareList) {
    foreach ($soft in $Config.SoftwareList) {
        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.Style = $CardCheckStyle
        $cb.Tag = $soft.Id
        $cb.IsChecked = $false

        $sp = New-Object System.Windows.Controls.StackPanel
        $tbName = New-Object System.Windows.Controls.TextBlock
        $tbName.Text = $soft.Name
        $tbName.FontSize = 13
        $tbName.FontWeight = "SemiBold"
        $tbName.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "TextPrimary")

        $tbId = New-Object System.Windows.Controls.TextBlock
        $tbId.Text = $soft.Id
        $tbId.FontSize = 10.5
        $tbId.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "TextMuted")

        $sp.Children.Add($tbName) | Out-Null
        $sp.Children.Add($tbId) | Out-Null
        $cb.Content = $sp

        $cb.Add_Checked($UpdateSummary)
        $cb.Add_Unchecked($UpdateSummary)
        $DynamicCheckboxes += $cb
        $pnlSoftwares.Children.Add($cb) | Out-Null
    }
}

foreach ($ctrl in @($rbDiagnostico, $rbExecucao)) {
    $ctrl.Add_Checked($UpdateSummary)
}
foreach ($tcb in $TweakCheckboxes) {
    $tcb.Add_Checked($UpdateSummary)
    $tcb.Add_Unchecked($UpdateSummary)
}

$btnTweakPresetCorp.Add_Click({
    foreach ($tcb in $TweakCheckboxes) {
        $tcb.IsChecked = ($CorpSafeTweaks -contains $tcb.Tag)
    }
    & $UpdateSummary
})
$btnTweakPresetClear.Add_Click({
    foreach ($tcb in $TweakCheckboxes) { $tcb.IsChecked = $false }
    & $UpdateSummary
})

$RunTweaksAction = {
    param([bool]$IsUndo)
    $SelectedTweaks = @($TweakCheckboxes | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
    if ($SelectedTweaks.Count -eq 0) {
        [System.Windows.MessageBox]::Show("Selecione pelo menos um tweak na lista.", "Nenhum tweak selecionado", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
        return
    }
    $ScriptFile = Join-Path $BaseDir "Invoke-Preventiva.ps1"
    if (-not (Test-Path -LiteralPath $ScriptFile)) {
        [System.Windows.MessageBox]::Show("Script base n$([char]0x00E3)o encontrado:`n$ScriptFile", "Erro", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
        return
    }

    $modeLabel = if ($IsUndo) { "TweaksUndo" } else { "Tweaks" }
    $ArgsList = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$ScriptFile`"",
        "-Mode", "`"$modeLabel`"", "-SubModo", "`"Execucao`"",
        "-Tasks", "`"None`"",
        "-Tweaks", "`"$($SelectedTweaks -join ',')`""
    )
    if ($IsUndo) { $ArgsList += "-UndoTweaks" }

    try {
        $btnExecutar.IsEnabled = $false
        $btnInstalarSoftwares.IsEnabled = $false
        $btnAplicarTweaks.IsEnabled = $false
        $btnDesfazerTweaks.IsEnabled = $false
        $btnExecutar.Content = if ($IsUndo) { "DESFAZENDO..." } else { "APLICANDO..." }
        $pbProgresso.Visibility = "Visible"
        $acaoTxt = if ($IsUndo) { "Desfazendo" } else { "Aplicando" }
        $txtStatus.Text = "$acaoTxt $($SelectedTweaks.Count) tweak(s)... Acompanhe na janela do console."

        $script:StartTime = Get-Date
        $script:CurrentProcess = Start-Process powershell -ArgumentList ($ArgsList -join " ") -WindowStyle Normal -PassThru
        $script:PollTimer.Start()
    } catch {
        $btnExecutar.IsEnabled = $true
        $btnInstalarSoftwares.IsEnabled = $true
        if ($btnUpgradeAllSoft) { $btnUpgradeAllSoft.IsEnabled = $true }
        $btnAplicarTweaks.IsEnabled = $true
        $btnDesfazerTweaks.IsEnabled = $true
        $btnExecutar.Content = "INICIAR PREVENTIVA"
        $pbProgresso.Visibility = "Collapsed"
        $txtStatus.Text = "Erro ao executar tweaks: $_"
    }
}

$btnAplicarTweaks.Add_Click({ & $RunTweaksAction $false })
$btnDesfazerTweaks.Add_Click({ & $RunTweaksAction $true })

$btnSelectAllSoft.Add_Click({
    foreach ($cb in $DynamicCheckboxes) { $cb.IsChecked = $true }
    & $UpdateSummary
})
$btnClearSoft.Add_Click({
    foreach ($cb in $DynamicCheckboxes) { $cb.IsChecked = $false }
    & $UpdateSummary
})

$btnInstalarSoftwares.Add_Click({
    $Softs = @($DynamicCheckboxes | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
    if ($Softs.Count -eq 0) {
        [System.Windows.MessageBox]::Show("Selecione pelo menos um software na lista para instalar.", "Nenhum software selecionado", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
        return
    }

    $ScriptFile = Join-Path $BaseDir "Invoke-Preventiva.ps1"
    if (-not (Test-Path -LiteralPath $ScriptFile)) {
        [System.Windows.MessageBox]::Show("Script base n$([char]0x00E3)o encontrado:`n$ScriptFile", "Erro", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
        return
    }

    $ArgsList = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$ScriptFile`"",
        "-Mode", "`"Softwares`"", "-SubModo", "`"Execucao`"",
        "-Tasks", "`"None`"",
        "-SoftwareToInstall", "`"$($Softs -join ',')`""
    )

    try {
        $btnExecutar.IsEnabled = $false
        $btnInstalarSoftwares.IsEnabled = $false
        $btnAplicarTweaks.IsEnabled = $false
        $btnDesfazerTweaks.IsEnabled = $false
        $btnExecutar.Content = "INSTALANDO..."
        $pbProgresso.Visibility = "Visible"
        $txtStatus.Text = "Instalando $($Softs.Count) software(s) via Winget... Acompanhe na janela do console."

        $script:StartTime = Get-Date
        $script:CurrentProcess = Start-Process powershell -ArgumentList ($ArgsList -join " ") -WindowStyle Normal -PassThru
        $script:PollTimer.Start()
    } catch {
        $btnExecutar.IsEnabled = $true
        $btnInstalarSoftwares.IsEnabled = $true
        if ($btnUpgradeAllSoft) { $btnUpgradeAllSoft.IsEnabled = $true }
        $btnAplicarTweaks.IsEnabled = $true
        $btnDesfazerTweaks.IsEnabled = $true
        $btnExecutar.Content = "INICIAR PREVENTIVA"
        $pbProgresso.Visibility = "Collapsed"
        $txtStatus.Text = "Erro ao iniciar instala$([char]0x00E7)$([char]0x00E3)o: $_"
    }
})

# Atalhos de Relatorios e Ferramentas
$btnAbrirPastaLogs.Add_Click({
    if (-not (Test-Path -LiteralPath $OutputFolder)) {
        New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
    }
    Start-Process explorer.exe -ArgumentList "`"$OutputFolder`""
})

$btnAbrirUltimoRelatorio.Add_Click({
    $latest = Get-ChildItem -LiteralPath $OutputFolder -Filter "Relatorio_*.html" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latest) {
        Start-Process $latest.FullName
    } else {
        [System.Windows.MessageBox]::Show("Nenhum relat$([char]0x00F3)rio HTML encontrado ainda em:`n$OutputFolder", "Relat$([char]0x00F3)rios", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
    }
})

$btnAbrirUtility.Add_Click({
    $utilBat = Join-Path $BaseDir "Rodar-Utilitario.bat"
    $utilPs1 = Join-Path $BaseDir "TechFontes-Utility.ps1"
    if (Test-Path -LiteralPath $utilBat) {
        Start-Process $utilBat
    } elseif (Test-Path -LiteralPath $utilPs1) {
        Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$utilPs1`""
    } else {
        [System.Windows.MessageBox]::Show("TechFontes-Utility n$([char]0x00E3)o encontrado na pasta.", "Aviso", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
    }
})

$btnAgendarSemanal.Add_Click({
    $sched = Join-Path $BaseDir "Install-Agendamento.ps1"
    if (Test-Path -LiteralPath $sched) {
        Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$sched`"" -Verb RunAs
    } else {
        [System.Windows.MessageBox]::Show("Script Install-Agendamento.ps1 n$([char]0x00E3)o encontrado.", "Aviso", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
    }
})

$btnAbrirConfig.Add_Click({
    if (Test-Path -LiteralPath $ConfigFile) {
        Start-Process notepad.exe -ArgumentList "`"$ConfigFile`""
    }
})

# Execucao Assincrona
$script:CurrentProcess = $null
$script:StartTime = $null
$script:PollTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:PollTimer.Interval = [TimeSpan]::FromMilliseconds(500)

$script:PollTimer.Add_Tick({
    if ($script:CurrentProcess -and -not $script:CurrentProcess.HasExited) {
        $elapsed = (Get-Date) - $script:StartTime
        $txtStatus.Text = "Executando... tempo decorrido: $($elapsed.ToString('mm\:ss'))"
    } else {
        $script:PollTimer.Stop()
        $pbProgresso.Visibility = "Collapsed"
        $btnExecutar.IsEnabled = $true
        $btnInstalarSoftwares.IsEnabled = $true
        if ($btnUpgradeAllSoft) { $btnUpgradeAllSoft.IsEnabled = $true }
        $btnAplicarTweaks.IsEnabled = $true
        $btnDesfazerTweaks.IsEnabled = $true
        $btnExecutar.Content = "INICIAR PREVENTIVA"

        $exitCode = if ($script:CurrentProcess) { $script:CurrentProcess.ExitCode } else { 0 }
        $script:CurrentProcess = $null

        if ($exitCode -eq 0) {
            $txtStatus.Text = "Conclu$([char]0x00ED)do! Relat$([char]0x00F3)rio salvo em $OutputFolder"
            $res = [System.Windows.MessageBox]::Show(
                "Opera$([char]0x00E7)$([char]0x00E3)o finalizada com sucesso!`n`nDeseja abrir o relat$([char]0x00F3)rio HTML gerado agora?",
                "Tech Fontes - Conclu$([char]0x00ED)do",
                [System.Windows.MessageBoxButton]::YesNo,
                [System.Windows.MessageBoxImage]::Information
            )
            if ($res -eq [System.Windows.MessageBoxResult]::Yes) {
                $latest = Get-ChildItem -LiteralPath $OutputFolder -Filter "Relatorio_*.html" -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending | Select-Object -First 1
                if ($latest) { Start-Process $latest.FullName }
            }
        } else {
            $txtStatus.Text = "Finalizado com c$([char]0x00F3)digo $exitCode. Verifique os logs em $OutputFolder"
        }
    }
})

$btnExecutar.Add_Click({
    $Mode = if ($script:ActivePresetName) { $script:ActivePresetName } else { "Personalizado" }
    $SubModo = if ($rbExecucao.IsChecked) { "Execucao" } else { "Diagnostico" }

    $SelectedTasks = @($TaskCheckboxes | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
    $SelectedTweaks = @($TweakCheckboxes | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
    $Softs = @($DynamicCheckboxes | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
    $HasPowerOpt = ($SelectedTweaks.Count -gt 0 -and $SubModo -eq "Execucao")

    if ($SelectedTasks.Count -eq 0 -and $Softs.Count -eq 0 -and -not $HasPowerOpt) {
        [System.Windows.MessageBox]::Show("Selecione pelo menos uma tarefa, tweak ou software para executar.", "Nenhuma a$([char]0x00E7)$([char]0x00E3)o selecionada", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
        return
    }

    $ScriptFile = Join-Path $BaseDir "Invoke-Preventiva.ps1"
    if (-not (Test-Path -LiteralPath $ScriptFile)) {
        [System.Windows.MessageBox]::Show("Script base n$([char]0x00E3)o encontrado:`n$ScriptFile", "Erro", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
        return
    }

    $ArgsList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$ScriptFile`"", "-Mode", "`"$Mode`"", "-SubModo", "`"$SubModo`"")
    $TasksArg = if ($SelectedTasks.Count -gt 0) { $SelectedTasks -join ',' } else { "None" }
    $ArgsList += "-Tasks"
    $ArgsList += "`"$TasksArg`""
    if ($SelectedTweaks.Count -gt 0) {
        $ArgsList += "-Tweaks"
        $ArgsList += "`"$($SelectedTweaks -join ',')`""
    }
    if ($Softs.Count -gt 0) {
        $ArgsList += "-SoftwareToInstall"
        $ArgsList += "`"$($Softs -join ',')`""
    }

    try {
        $btnExecutar.IsEnabled = $false
        $btnInstalarSoftwares.IsEnabled = $false
        $btnAplicarTweaks.IsEnabled = $false
        $btnDesfazerTweaks.IsEnabled = $false
        $btnExecutar.Content = "EXECUTANDO..."
        $pbProgresso.Visibility = "Visible"
        $txtStatus.Text = "Iniciando $Mode ($SubModo)... Acompanhe na janela do console."

        $script:StartTime = Get-Date
        $script:CurrentProcess = Start-Process powershell -ArgumentList ($ArgsList -join " ") -WindowStyle Normal -PassThru
        $script:PollTimer.Start()
    } catch {
        $btnExecutar.IsEnabled = $true
        $btnInstalarSoftwares.IsEnabled = $true
        if ($btnUpgradeAllSoft) { $btnUpgradeAllSoft.IsEnabled = $true }
        $btnAplicarTweaks.IsEnabled = $true
        $btnDesfazerTweaks.IsEnabled = $true
        $btnExecutar.Content = "INICIAR PREVENTIVA"
        $pbProgresso.Visibility = "Collapsed"
        $txtStatus.Text = "Erro ao iniciar o processo: $_"
    }
})

# Popular Perfis Pos-Formatacao (settings.json)
$SecondaryBtnStyle = $Window.FindResource("SecondaryButton")
if ($Config -and $Config.OnboardingProfiles -and $pnlOnboardingProfiles) {
    foreach ($prof in $Config.OnboardingProfiles) {
        $btnP = New-Object System.Windows.Controls.Button
        $btnP.Style = $SecondaryBtnStyle
        $btnP.Content = "Perfil: $($prof.Name)"
        $btnP.ToolTip = $prof.Description
        $btnP.HorizontalAlignment = "Stretch"
        $btnP.Margin = New-Object System.Windows.Thickness(0, 0, 0, 7)
        $btnP.Padding = New-Object System.Windows.Thickness(12, 9, 12, 9)
        $btnP.Tag = $prof
        $btnP.Add_Click({
            $p = $this.Tag
            if ($p.Preset) { & $ApplyPreset $p.Preset }
            foreach ($tcb in $TweakCheckboxes) {
                $tcb.IsChecked = ($p.Tweaks -contains $tcb.Tag)
            }
            foreach ($scb in $DynamicCheckboxes) {
                $scb.IsChecked = ($p.Softwares -contains $scb.Tag)
            }
            $rbExecucao.IsChecked = $true
            & $UpdateSummary
            $txtStatus.Text = "Perfil '$($p.Name)' carregado! Clique em INICIAR PREVENTIVA para aplicar."
        })
        $pnlOnboardingProfiles.Children.Add($btnP) | Out-Null
    }
}

# Botao Atualizar Todos os Apps (winget upgrade --all)
if ($btnUpgradeAllSoft) {
    $btnUpgradeAllSoft.Add_Click({
        $ScriptFile = Join-Path $BaseDir "Invoke-Preventiva.ps1"
        if (-not (Test-Path -LiteralPath $ScriptFile)) { return }
        $ArgsList = @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$ScriptFile`"",
            "-Mode", "`"WingetUpgrade`"", "-SubModo", "`"Execucao`"",
            "-Tasks", "`"None`"", "-UpgradeAllSoftware"
        )
        try {
            $btnExecutar.IsEnabled = $false
            $btnInstalarSoftwares.IsEnabled = $false
            $btnUpgradeAllSoft.IsEnabled = $false
            $btnAplicarTweaks.IsEnabled = $false
            $btnDesfazerTweaks.IsEnabled = $false
            $btnExecutar.Content = "ATUALIZANDO..."
            $pbProgresso.Visibility = "Visible"
            $txtStatus.Text = "Atualizando todos os apps instalados via Winget... Acompanhe no console."
            $script:StartTime = Get-Date
            $script:CurrentProcess = Start-Process powershell -ArgumentList ($ArgsList -join " ") -WindowStyle Normal -PassThru
            $script:PollTimer.Start()
        } catch {
            $btnExecutar.IsEnabled = $true
            $btnInstalarSoftwares.IsEnabled = $true
        if ($btnUpgradeAllSoft) { $btnUpgradeAllSoft.IsEnabled = $true }
            $btnUpgradeAllSoft.IsEnabled = $true
            $btnAplicarTweaks.IsEnabled = $true
            $btnDesfazerTweaks.IsEnabled = $true
            $btnExecutar.Content = "INICIAR PREVENTIVA"
            $pbProgresso.Visibility = "Collapsed"
            $txtStatus.Text = "Erro ao iniciar atualiza$([char]0x00E7)$([char]0x00E3)o Winget: $_"
        }
    })
}

# Aba Rede & Suporte Rapido
$RefreshNetworkUI = {
    try {
        if (Get-Command Get-PreventivaNetworkSummary -ErrorAction SilentlyContinue) {
            $info = Get-PreventivaNetworkSummary
            $txtNetAdapter.Text  = $info.Adapter
            $txtNetLocalIP.Text  = $info.LocalIP
            $txtNetGateway.Text  = $info.Gateway
            $txtNetDns.Text      = $info.DnsList
            $txtNetMac.Text      = $info.Mac
            $txtNetPublicIP.Text = $info.PublicIP
            $txtNetLatency.Text  = $info.Latency
            $txtNetActionResult.Text = "Informa$([char]0x00E7)$([char]0x00F5)es de rede atualizadas ($(Get-Date -Format 'HH:mm:ss'))."
        }
    } catch {
        $txtNetActionResult.Text = "Falha ao ler rede: $_"
    }
}

$btnRefreshNet.Add_Click($RefreshNetworkUI)
$btnDnsCloudflare.Add_Click({
    try { $txtNetActionResult.Text = (Set-PreventivaDns -Provider "Cloudflare"); & $RefreshNetworkUI } catch { $txtNetActionResult.Text = "Erro: $_" }
})
$btnDnsGoogle.Add_Click({
    try { $txtNetActionResult.Text = (Set-PreventivaDns -Provider "Google"); & $RefreshNetworkUI } catch { $txtNetActionResult.Text = "Erro: $_" }
})
$btnDnsQuad9.Add_Click({
    try { $txtNetActionResult.Text = (Set-PreventivaDns -Provider "Quad9"); & $RefreshNetworkUI } catch { $txtNetActionResult.Text = "Erro: $_" }
})
$btnDnsDhcp.Add_Click({
    try { $txtNetActionResult.Text = (Set-PreventivaDns -Provider "DHCP"); & $RefreshNetworkUI } catch { $txtNetActionResult.Text = "Erro: $_" }
})
$btnQuickFlushDns.Add_Click({
    try { ipconfig /flushdns | Out-Null; $txtNetActionResult.Text = "Flush DNS executado com sucesso ($(Get-Date -Format 'HH:mm:ss'))." } catch { $txtNetActionResult.Text = "Erro: $_" }
})
$btnQuickRenewIp.Add_Click({
    try { $txtNetActionResult.Text = (Invoke-PreventivaRenewIp); & $RefreshNetworkUI } catch { $txtNetActionResult.Text = "Erro: $_" }
})
$btnQuickSpooler.Add_Click({
    try { $txtNetActionResult.Text = (Restart-PreventivaPrintSpooler) } catch { $txtNetActionResult.Text = "Erro: $_" }
})
$btnQuickNcpa.Add_Click({ Start-Process "ncpa.cpl" })
$btnQuickDevMgmt.Add_Click({ Start-Process "devmgmt.msc" })

& $ApplyPreset "Light"
& $ApplyTheme $script:ThemeMode
$Window.ShowDialog() | Out-Null
