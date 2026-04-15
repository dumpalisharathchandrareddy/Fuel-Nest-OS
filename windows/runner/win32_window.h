#ifndef RUNNER_WIN32_WINDOW_H_
#define RUNNER_WIN32_WINDOW_H_

#include <windows.h>
#include <functional>
#include <memory>
#include <string>

// A class abstraction for a high DPI-aware Win32 Window. Intended to be
// inherited from by classes that wish to specialize with custom
// rendering and input handling
class Win32Window {
 public:
  struct Point {
    unsigned int x;
    unsigned int y;
    Point(unsigned int x, unsigned int y) : x(x), y(y) {}
  };

  struct Size {
    unsigned int width;
    unsigned int height;
    Size(unsigned int width, unsigned int height)
        : width(width), height(height) {}
  };

  Win32Window();
  virtual ~Win32Window();

  // Creates a win32 window with |title| that is positioned and sized using
  // |origin| and |size|. New windows are created on the default monitor. Window
  // creation can fail if, for example, the monitor information is unavailable.
  // Returns bool indicating whether or not the window was created successfully.
  bool Create(const std::wstring& title, const Point& origin, const Size& size);

  // Release OS resources associated with window.
  void Destroy();

  // Inserts |content| into the window tree.
  void SetChildContent(HWND content);

  // Returns the backing Window handle to enable clients to set icon and other
  // window properties. Returns nullptr if the window has been destroyed.
  HWND GetHandle();

  // If true, closing this window will quit the application.
  void SetQuitOnClose(bool quit_on_close);

  // Return a RECT representing the bounds of the current client area.
  RECT GetClientArea();

  // Prevent copying.
  Win32Window(Win32Window const&) = delete;
  Win32Window& operator=(Win32Window const&) = delete;

 protected:
  // Registers a window class with default style attributes, cursor and
  // icon.
  WNDCLASS RegisterWindowClass();

  // OS callback called by message pump. Handles the WM_NCCREATE message which
  // is passed when the non-client area is being created and enables automatic
  // non-client DPI scaling so that the non-client area automatically responds
  // to changes in DPI. All other messages are handled by
  // MessageHandler.
  static LRESULT CALLBACK WndProc(HWND const window, UINT const message,
                                   WPARAM const wparam,
                                   LPARAM const lparam) noexcept;

  // Processes and route salient window messages for mouse handling,
  // size change and DPI. Delegates handling of these to member overloads that
  // inheriting classes can handle.
  LRESULT
  HandleMessage(UINT const message, WPARAM const wparam,
                LPARAM const lparam) noexcept;

  // Called when CreateAndShow is called, allowing subclasses to set
  // their own window flags before the window is created.
  virtual bool OnCreate();

  // Called when Destroy is called.
  virtual void OnDestroy();

  // Handles messages not handled by HandleMessage, including the
  // WM_DESTROY message.
  virtual LRESULT
  MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                 LPARAM const lparam) noexcept;

  // Called when the DPI changes either when a there is a DPI change
  // event or on Show of the window. Implementations are responsible for
  // updating |point| and |size| per the new DPI.
  virtual void OnDpiScale(UINT nDpi);

  // Called when a child window's size changes.
  virtual void OnResize(UINT width, UINT height);

  // Show the window.
  void Show();

 private:
  friend class WindowClassRegistrar;

  // OS callback called by message pump.
  static LRESULT CALLBACK WndProc(HWND const window, UINT const message,
                                   WPARAM const wparam,
                                   LPARAM const lparam,
                                   UINT_PTR const subclassId,
                                   DWORD_PTR const refData) noexcept;

  // Retrieves a class instance pointer for |window|
  static Win32Window* GetThisFromHandle(HWND const window) noexcept;

  // Update the window size and DPI for the given |monitor|.
  void UpdateThemeChanges();

  bool quit_on_close_ = false;

  // window handle for top level window.
  HWND window_handle_ = nullptr;

  // handle for hosted content.
  HWND child_content_ = nullptr;
};

#endif  // RUNNER_WIN32_WINDOW_H_
