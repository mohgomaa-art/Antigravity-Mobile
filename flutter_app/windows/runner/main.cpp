#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // Create a Win32 Job Object with KILL_ON_JOB_CLOSE limit so all child processes
  // (antigravity_bridge, cloudflared, adb) are guaranteed to be terminated by the OS
  // kernel when this process terminates, even if forcibly killed or crashed.
  HANDLE hJob = ::CreateJobObjectW(nullptr, nullptr);
  if (hJob != nullptr) {
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION jeli = { 0 };
    jeli.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    ::SetInformationJobObject(hJob, JobObjectExtendedLimitInformation, &jeli, sizeof(jeli));
    ::AssignProcessToJobObject(hJob, ::GetCurrentProcess());
  }

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Antigravity Fleet Station", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  // Synchronously terminate any child bridge or cloudflared tunnel processes
  // to guarantee zero orphaned background processes remain after window closes.
  STARTUPINFOW si = { sizeof(si) };
  si.dwFlags = STARTF_USESHOWWINDOW;
  si.wShowWindow = SW_HIDE;
  PROCESS_INFORMATION pi;
  wchar_t killCmd[] = L"taskkill.exe /F /T /IM antigravity_bridge.exe /IM cloudflared.exe";
  if (::CreateProcessW(nullptr, killCmd, nullptr, nullptr, FALSE, CREATE_NO_WINDOW, nullptr, nullptr, &si, &pi)) {
    ::WaitForSingleObject(pi.hProcess, 1500);
    ::CloseHandle(pi.hProcess);
    ::CloseHandle(pi.hThread);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
