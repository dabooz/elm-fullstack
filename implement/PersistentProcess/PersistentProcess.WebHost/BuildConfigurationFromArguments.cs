using System;
using System.Collections.Immutable;
using System.IO;
using System.Linq;
using System.Text;

namespace Kalmit.PersistentProcess.WebHost
{
    static public class BuildConfigurationFromArguments
    {
        static public (
            Composition.TreeComponent sourceTree,
            string filteredSourceCompositionId,
            byte[] configZipArchive)
            BuildConfigurationZipArchiveFromPath(string sourcePath)
        {
            var loadFromPathResult = LoadFromPath.LoadTreeFromPath(sourcePath);

            if (loadFromPathResult?.Ok == null)
            {
                throw new Exception("Failed to load from path '" + sourcePath + "': " + loadFromPathResult?.Err);
            }

            var sourceTree = loadFromPathResult.Ok.tree;

            /*
            TODO: Provide a better way to avoid unnecessary files ending up in the config: Get the source files from git.
            */
            var filteredSourceTree =
                loadFromPathResult.Ok.comesFromLocalFilesystem
                ?
                RemoveNoiseFromTreeComingFromLocalFileSystem(sourceTree)
                :
                sourceTree;

            var filteredSourceComposition = Composition.FromTree(filteredSourceTree);

            var filteredSourceCompositionId = CommonConversion.StringBase16FromByteArray(Composition.GetHash(filteredSourceComposition));

            Console.WriteLine("Loaded source composition " + filteredSourceCompositionId + " from '" + sourcePath + "'.");

            var configZipArchive =
                BuildConfigurationZipArchive(sourceComposition: filteredSourceComposition);

            return
                (sourceTree: sourceTree,
                filteredSourceCompositionId: filteredSourceCompositionId,
                configZipArchive: configZipArchive);
        }

        static public Composition.TreeComponent RemoveNoiseFromTreeComingFromLocalFileSystem(
            Composition.TreeComponent originalTree)
        {
            if (originalTree.TreeContent == null)
                return originalTree;

            Composition.TreeComponent getComponentFromStringName(string name) =>
                originalTree.TreeContent.FirstOrDefault(c => c.name.SequenceEqual(Encoding.UTF8.GetBytes(name))).component;

            var elmJson = getComponentFromStringName("elm.json");

            bool keepNode((IImmutableList<byte> name, Composition.TreeComponent component) node)
            {
                if (elmJson != null && node.name.SequenceEqual(Encoding.UTF8.GetBytes("elm-stuff")))
                    return false;

                return true;
            }

            return new Composition.TreeComponent
            {
                TreeContent =
                    originalTree.TreeContent
                    .Where(keepNode)
                    .Select(child => (child.name, RemoveNoiseFromTreeComingFromLocalFileSystem(child.component))).ToImmutableList()
            };
        }

        static public byte[] BuildConfigurationZipArchive(Composition.Component sourceComposition)
        {
            var parseSourceAsTree = Composition.ParseAsTree(sourceComposition);

            if (parseSourceAsTree.Ok == null)
                throw new Exception("Failed to map source to tree.");

            var sourceFiles =
                ElmApp.ToFlatDictionaryWithPathComparer(
                    parseSourceAsTree.Ok.EnumerateBlobsTransitive()
                    .Select(sourceFilePathAndContent =>
                        (path: (IImmutableList<string>)sourceFilePathAndContent.path.Select(pathComponent => Encoding.UTF8.GetString(pathComponent.ToArray())).ToImmutableList(),
                        sourceFilePathAndContent.blobContent))
                        .ToImmutableList());

            return ZipArchive.ZipArchiveFromEntries(sourceFiles);
        }

        static string FindDirectoryUpwardContainingElmJson(string searchBeginDirectory)
        {
            var currentDirectory = searchBeginDirectory;

            while (true)
            {
                if (!(0 < currentDirectory?.Length))
                    return null;

                if (File.Exists(Path.Combine(currentDirectory, "elm.json")))
                    return currentDirectory;

                currentDirectory = Path.GetDirectoryName(currentDirectory);
            }
        }
    }
}
