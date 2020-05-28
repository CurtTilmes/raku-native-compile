extern "C"
#if defined(_MSVC_LANG)
__declspec(dllexport)
#endif
const char *hello()
{
    return "Hello, World!\n";
}
