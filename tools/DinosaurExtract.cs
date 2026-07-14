using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Text;

// Estrae dinosaur_sprite2.png senza ricampionare i pixel originali.
// Lo sheet contiene 14 colonne, due righe alte 65 px e una cella vuota.
public static class DinosaurExtract
{
	const int CellWidth = 64;
	const int CellHeight = 65;
	const int Columns = 14;
	const int Rows = 2;

	// I fondali dello sheet sono quattro varianti dello stesso verde. Una
	// regola cromatica e' piu' robusta di un singolo color-key e non tocca la
	// palette marrone/rossa, bianca, grigia e nera del dinosauro.
	static bool IsBackdrop(Color c)
	{
		return c.A > 0 && c.G > c.R * 2.0 && c.G > c.B * 1.22;
	}

	static Bitmap ExtractCell(Bitmap source, int column, int row, out int opaquePixels)
	{
		var frame = new Bitmap(CellWidth, CellHeight, PixelFormat.Format32bppArgb);
		opaquePixels = 0;
		int sourceY = row * CellHeight;
		for (int y = 0; y < CellHeight && sourceY + y < source.Height; y++)
		for (int x = 0; x < CellWidth; x++)
		{
			Color pixel = source.GetPixel(column * CellWidth + x, sourceY + y);
			if (IsBackdrop(pixel))
			{
				frame.SetPixel(x, y, Color.Transparent);
				continue;
			}
			frame.SetPixel(x, y, pixel);
			opaquePixels++;
		}
		return frame;
	}

	public static void Run(string inputPath, string outputDirectory, string contactSheetPath)
	{
		Directory.CreateDirectory(outputDirectory);
		Directory.CreateDirectory(Path.GetDirectoryName(contactSheetPath));
		var frames = new List<Bitmap>();
		var names = new List<string>();
		var manifest = new StringBuilder();
		manifest.AppendLine("[");

		using (var source = new Bitmap(inputPath))
		{
			if (source.Width != CellWidth * Columns || source.Height < CellHeight * Rows)
				throw new InvalidDataException(String.Format(
					"Unexpected sheet size {0}x{1}; expected {2}x{3} or taller.",
					source.Width, source.Height, CellWidth * Columns, CellHeight * Rows));

			int index = 0;
			for (int row = 0; row < Rows; row++)
			for (int column = 0; column < Columns; column++)
			{
				int opaque;
				Bitmap frame = ExtractCell(source, column, row, out opaque);
				if (opaque < 16) // la cella riga 1 / colonna 1 e' intenzionalmente vuota
				{
					frame.Dispose();
					continue;
				}
				string name = String.Format("dinosaur_{0:D2}.png", index);
				frame.Save(Path.Combine(outputDirectory, name), ImageFormat.Png);
				frames.Add(frame);
				names.Add(name);
				manifest.AppendFormat(
					"  {{\"file\":\"{0}\",\"source_row\":{1},\"source_column\":{2},\"opaque_pixels\":{3}}},\n",
					name, row, column, opaque);
				Console.WriteLine("{0} <- row {1}, column {2} ({3} opaque px)",
					name, row, column, opaque);
				index++;
			}
		}

		if (manifest[manifest.Length - 2] == ',')
			manifest.Remove(manifest.Length - 2, 1);
		manifest.AppendLine("]");
		File.WriteAllText(Path.Combine(outputDirectory, "frames.json"), manifest.ToString());

		const int previewColumns = 7;
		const int tileWidth = 88;
		const int tileHeight = 88;
		int previewRows = (frames.Count + previewColumns - 1) / previewColumns;
		using (var contact = new Bitmap(previewColumns * tileWidth, previewRows * tileHeight,
			PixelFormat.Format32bppArgb))
		using (var graphics = Graphics.FromImage(contact))
		using (var dark = new SolidBrush(Color.FromArgb(255, 35, 42, 48)))
		using (var light = new SolidBrush(Color.FromArgb(255, 55, 64, 72)))
		using (var labelBrush = new SolidBrush(Color.White))
		using (var font = new Font("Arial", 8, FontStyle.Bold))
		{
			graphics.Clear(Color.FromArgb(255, 24, 29, 34));
			graphics.InterpolationMode = InterpolationMode.NearestNeighbor;
			graphics.PixelOffsetMode = PixelOffsetMode.Half;
			for (int i = 0; i < frames.Count; i++)
			{
				int tx = (i % previewColumns) * tileWidth;
				int ty = (i / previewColumns) * tileHeight;
				for (int cy = 0; cy < 5; cy++)
				for (int cx = 0; cx < 5; cx++)
					graphics.FillRectangle(((cx + cy) & 1) == 0 ? dark : light,
						tx + 8 + cx * 13, ty + 2 + cy * 13, 13, 13);
				graphics.DrawImageUnscaled(frames[i], tx + 8, ty + 2);
				graphics.DrawString(names[i].Replace(".png", ""), font, labelBrush, tx + 7, ty + 69);
			}
			contact.Save(contactSheetPath, ImageFormat.Png);
		}

		foreach (Bitmap frame in frames)
			frame.Dispose();
		Console.WriteLine("Extracted {0} frames to {1}", names.Count, outputDirectory);
	}

	// dinosaur_sprite3.png usa cinque colonne; la prima riga e' alta 64 px e
	// la seconda 63. I ritagli vengono allineati in basso sulla stessa tela
	// 64x65 dei frame precedenti e aggiunti senza sovrascriverli.
	public static void AppendThirdSheet(string inputPath, string outputDirectory,
		string contactSheetPath)
	{
		int nextIndex = Directory.GetFiles(outputDirectory, "dinosaur_*.png").Length;
		var newEntries = new List<string>();
		using (var source = new Bitmap(inputPath))
		{
			if (source.Width != 320 || source.Height != 127)
				throw new InvalidDataException(String.Format(
					"Unexpected third sheet size {0}x{1}; expected 320x127.",
					source.Width, source.Height));
			int[] rowStarts = { 0, 64 };
			int[] rowHeights = { 64, 63 };
			for (int row = 0; row < 2; row++)
			for (int column = 0; column < 5; column++)
			{
				int opaque;
				using (Bitmap frame = ExtractVariableCell(source, column, rowStarts[row],
					rowHeights[row], out opaque))
				{
					if (opaque < 16)
						continue;
					string name = String.Format("dinosaur_{0:D2}.png", nextIndex++);
					frame.Save(Path.Combine(outputDirectory, name), ImageFormat.Png);
					newEntries.Add(String.Format(
						"  {{\"file\":\"{0}\",\"source_sheet\":\"dinosaur_sprite3.png\",\"source_row\":{1},\"source_column\":{2},\"opaque_pixels\":{3}}}",
						name, row, column, opaque));
					Console.WriteLine("{0} <- sheet3 row {1}, column {2} ({3} opaque px)",
						name, row, column, opaque);
				}
			}
		}
		AppendManifest(Path.Combine(outputDirectory, "frames.json"), newEntries);
		BuildContactSheet(outputDirectory, contactSheetPath);
		Console.WriteLine("Appended {0} frames; total is now {1}", newEntries.Count, nextIndex);
	}

	static Bitmap ExtractVariableCell(Bitmap source, int column, int sourceY,
		int sourceHeight, out int opaquePixels)
	{
		var frame = new Bitmap(CellWidth, CellHeight, PixelFormat.Format32bppArgb);
		opaquePixels = 0;
		int destinationY = CellHeight - sourceHeight;
		for (int y = 0; y < sourceHeight; y++)
		for (int x = 0; x < CellWidth; x++)
		{
			Color pixel = source.GetPixel(column * CellWidth + x, sourceY + y);
			if (IsBackdrop(pixel))
			{
				frame.SetPixel(x, destinationY + y, Color.Transparent);
				continue;
			}
			frame.SetPixel(x, destinationY + y, pixel);
			opaquePixels++;
		}
		return frame;
	}

	static void AppendManifest(string manifestPath, List<string> entries)
	{
		string current = File.ReadAllText(manifestPath).TrimEnd();
		int closingBracket = current.LastIndexOf(']');
		if (closingBracket < 0)
			throw new InvalidDataException("frames.json is not a JSON array.");
		string prefix = current.Substring(0, closingBracket).TrimEnd();
		var output = new StringBuilder(prefix);
		if (!prefix.EndsWith("["))
			output.AppendLine(",");
		for (int i = 0; i < entries.Count; i++)
		{
			output.Append(entries[i]);
			output.AppendLine(i + 1 < entries.Count ? "," : "");
		}
		output.AppendLine("]");
		File.WriteAllText(manifestPath, output.ToString());
	}

	static void BuildContactSheet(string outputDirectory, string contactSheetPath)
	{
		string[] files = Directory.GetFiles(outputDirectory, "dinosaur_*.png");
		Array.Sort(files, StringComparer.OrdinalIgnoreCase);
		const int previewColumns = 7;
		const int tileWidth = 88;
		const int tileHeight = 88;
		int previewRows = (files.Length + previewColumns - 1) / previewColumns;
		using (var contact = new Bitmap(previewColumns * tileWidth, previewRows * tileHeight,
			PixelFormat.Format32bppArgb))
		using (var graphics = Graphics.FromImage(contact))
		using (var dark = new SolidBrush(Color.FromArgb(255, 35, 42, 48)))
		using (var light = new SolidBrush(Color.FromArgb(255, 55, 64, 72)))
		using (var labelBrush = new SolidBrush(Color.White))
		using (var font = new Font("Arial", 8, FontStyle.Bold))
		{
			graphics.Clear(Color.FromArgb(255, 24, 29, 34));
			graphics.InterpolationMode = InterpolationMode.NearestNeighbor;
			graphics.PixelOffsetMode = PixelOffsetMode.Half;
			for (int i = 0; i < files.Length; i++)
			using (var frame = new Bitmap(files[i]))
			{
				int tx = (i % previewColumns) * tileWidth;
				int ty = (i / previewColumns) * tileHeight;
				for (int cy = 0; cy < 5; cy++)
				for (int cx = 0; cx < 5; cx++)
					graphics.FillRectangle(((cx + cy) & 1) == 0 ? dark : light,
						tx + 8 + cx * 13, ty + 2 + cy * 13, 13, 13);
				graphics.DrawImageUnscaled(frame, tx + 8, ty + 2);
				graphics.DrawString(Path.GetFileNameWithoutExtension(files[i]), font,
					labelBrush, tx + 7, ty + 69);
			}
			contact.Save(contactSheetPath, ImageFormat.Png);
		}
	}
}
