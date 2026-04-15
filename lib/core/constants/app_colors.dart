import 'package:flutter/material.dart';

/// Design tokens mirroring the existing web app's tokens.css
/// Dark theme — matches the fuel station management system look
class AppColors {
  AppColors._();

  // ── Backgrounds ──────────────────────────────────────────────────────────
  static const bgApp = Color(0xFF0A0C10);
  static const bgSurface = Color(0xFF0F1117);
  static const bgCard = Color(0xFF141720);
  static const bgHover = Color(0x0AFFFFFF);
  static const bgActive = Color(0x1460A5FA);

  // ── Borders ───────────────────────────────────────────────────────────────
  static const border = Color(0x0FFFFFFF);
  static const borderMd = Color(0x1AFFFFFF);

  // ── Text ──────────────────────────────────────────────────────────────────
  static const textPrimary = Color(0xE6FFFFFF);
  static const textSecondary = Color(0x80FFFFFF);
  static const textMuted = Color(0x40FFFFFF);

  // ── Accent ────────────────────────────────────────────────────────────────
  static const blue = Color(0xFF60A5FA);
  static const blueBg = Color(0x1A60A5FA);
  static const green = Color(0xFF4ADE80);
  static const greenBg = Color(0x1A4ADE80);
  static const red = Color(0xFFF87171);
  static const redBg = Color(0x1AF87171);
  static const amber = Color(0xFFFBBF24);
  static const amberBg = Color(0x1AFBBF24);
  static const purple = Color(0xFFA78BFA);
  static const purpleBg = Color(0x1AA78BFA);

  // ── Semantic aliases ──────────────────────────────────────────────────────
  static const primary = blue;
  static const primaryBg = blueBg;
  static const success = green;
  static const successBg = greenBg;
  static const error = red;
  static const errorBg = redBg;
  static const warning = amber;
  static const warningBg = amberBg;

  // ── Fuel type colors ──────────────────────────────────────────────────────
  static const petrol = Color(0xFF34D399);   // green
  static const diesel = Color(0xFFFBBF24);   // amber
  static const power = Color(0xFF60A5FA);    // blue
  static const cng = Color(0xFFA78BFA);      // purple
  static const lng = Color(0xFFF472B6);      // pink
}
