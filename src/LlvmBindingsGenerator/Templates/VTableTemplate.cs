using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;

using CppSharp.AST;

namespace LlvmBindingsGenerator.Templates
{
    internal partial class VTableTemplate
        : ICodeGenTemplate
    {
        public VTableTemplate( TranslationUnit tu )
        {
            Unit = tu;
        }

        public string ToolVersion => GetType( ).Assembly.GetAssemblyInformationalVersion( );

        public string? FileExtension => "cs";

        public string? SubFolder => string.Empty;

        public string Generate( )
        {
            return TransformText();
        }

        public string VTableName => Unit.FileNameWithoutExtension;

        public IEnumerable<Function> Functions
            => from func in Unit.Functions
               where !func.IsInline && !func.Ignore
               select func;

        public static string GetManagedFunctionPointerType(Function func)
        {
            // temp: force all methods to `void foo()`
            var bldr = new StringBuilder("delegate* unmanaged [Cdecl]<");
            for(int i = 0; i < func.Parameters.Count; ++i)
            {
                var param = func.Parameters[i];
                if( i > 0)
                {
                    bldr.Append(", ");
                }

                // handle types are processed as void* in signatures as there is no concept
                // of an opaque struct pointer typedef in C#
                if(param.Type.TryGetHandleDecl(out TypedefNameDecl? _))
                {
                    bldr.Append(CultureInfo.InvariantCulture, $"void*/*{param.Type}*//*{param.Name}*/");
                }
                else
                {
                    bldr.Append(CultureInfo.InvariantCulture, $"{param.Type.ToString()}/*{param.Name}*/");
                }
            }

            if (func.Parameters.Count > 0)
            {
                bldr.Append(", ");
            }

            bldr.Append(CultureInfo.InvariantCulture, $"{func.ReturnType.Type.ToString()}/*Return*/>");
            return bldr.ToString();
        }

        private readonly TranslationUnit Unit;
    }
}
