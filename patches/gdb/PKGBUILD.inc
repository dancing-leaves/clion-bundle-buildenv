[[ "$(declare -p source)"  =~ "declare -a" ]] || return 1
[[ "$(declare -p md5sums)" =~ "declare -a" ]] || return 1


source+=('gdb-fix-using-gnu-print.patch'

         # https://sourceware.org/bugzilla/show_bug.cgi?id=21078
         'gdb-7.12-dynamic-libs.patch'

         # Fix gdbserver not printing inferior PID on Windows
         'gdbserver-Output-PID-right-after-create_inferior-call.patch'

         # Bugzilla #13669: https://sourceware.org/bugzilla/attachment.cgi?id=8993&action=diff
         'CPP-10461-gdb-limit-cp_print_value_fields-recursion.patch')

md5sums+=('6b485bc8b1025610804fef9e111ade24'
          '225646ec91143b400e54c4a7cba4a674'
          'aaf3a9e88684c8606084c6e8073619ab'
          '7ce3fc34c6800e735c52895c7e1d8372')


gdb_enable_targets=(
    'i686-pc-mingw32'

    'i686-linux-gnu'
    'i686-w64-mingw32'
    'x86_64-linux-gnu'
    'x86_64-w64-mingw32'

    'aarch64-linux-gnu'
    'alpha-linux-gnu'
    'arm-linux-gnu'
    'arm-linux-gnueabi'
    'arm-linux-gnueabihf'
    'hppa-linux-gnu'
    'm68k-linux-gnu'
    'm68k-rtems'
    'mips-linux-gnu'
    'mipsel-linux-gnu'
    'mips64-linux-gnu'
    'mips64el-linux-gnu'
    'powerpc-linux-gnu'
    'powerpc-linux-gnuspe'
    'powerpc64le-linux-gnu'
    'powerpc64-linux-gnu'
    's390-linux-gnu'
    's390x-linux-gnu'
    'sh-linux-gnu'
    'sparc-linux-gnu'
    'sparc64-linux-gnu'
    'm32r-linux-gnu'
)

