using Amazon.Runtime;
using Amazon.S3;
using Amazon.S3.Model;
using FrameMind.Application.Abstractions;
using Microsoft.Extensions.Options;

namespace FrameMind.Infrastructure.Storage;

/// <summary>AWS S3 / Cloudflare R2 / MinIO storage with pre-signed (expiring) URLs.</summary>
public sealed class S3FileStorage : IFileStorage, IDisposable
{
    private readonly StorageOptions _opt;
    private readonly AmazonS3Client _client;
    private readonly AmazonS3Client _signer;

    public S3FileStorage(IOptions<StorageOptions> options)
    {
        _opt = options.Value;
        _client = CreateClient(_opt.ServiceUrl);
        _signer = string.IsNullOrWhiteSpace(_opt.PublicServiceUrl) ? _client : CreateClient(_opt.PublicServiceUrl);
    }

    private AmazonS3Client CreateClient(string? serviceUrl)
    {
        var config = new AmazonS3Config { ForcePathStyle = _opt.ForcePathStyle };
        if (!string.IsNullOrWhiteSpace(serviceUrl))
        {
            config.ServiceURL = serviceUrl;
            config.AuthenticationRegion = _opt.Region;
        }
        else
        {
            config.RegionEndpoint = Amazon.RegionEndpoint.GetBySystemName(_opt.Region);
        }

        return string.IsNullOrWhiteSpace(_opt.AccessKey)
            ? new AmazonS3Client(config)
            : new AmazonS3Client(new BasicAWSCredentials(_opt.AccessKey, _opt.SecretKey), config);
    }

    public async Task EnsureBucketAsync(CancellationToken ct)
    {
        if (!_opt.CreateBucketIfMissing) return;
        var buckets = await _client.ListBucketsAsync(ct);
        if (buckets.Buckets?.Any(b => b.BucketName == _opt.Bucket) == true) return;
        await _client.PutBucketAsync(new PutBucketRequest { BucketName = _opt.Bucket }, ct);
    }

    public async Task UploadAsync(string key, string localPath, string contentType, CancellationToken ct)
    {
        var request = new PutObjectRequest
        {
            BucketName = _opt.Bucket,
            Key = key,
            FilePath = localPath,
            ContentType = contentType,
        };
        if (_opt.ServerSideEncryption) request.ServerSideEncryptionMethod = ServerSideEncryptionMethod.AES256;
        await _client.PutObjectAsync(request, ct);
    }

    public Task DeleteAsync(string key, CancellationToken ct) =>
        _client.DeleteObjectAsync(new DeleteObjectRequest { BucketName = _opt.Bucket, Key = key }, ct);

    public Uri GetSignedUrl(string key, TimeSpan lifetime, string? downloadFileName = null)
    {
        var endpoint = _opt.PublicServiceUrl ?? _opt.ServiceUrl;
        var request = new GetPreSignedUrlRequest
        {
            BucketName = _opt.Bucket,
            Key = key,
            Verb = HttpVerb.GET,
            Expires = DateTime.UtcNow.Add(lifetime),
            Protocol = endpoint?.StartsWith("http://", StringComparison.OrdinalIgnoreCase) == true ? Protocol.HTTP : Protocol.HTTPS,
        };
        if (downloadFileName is not null)
            request.ResponseHeaderOverrides.ContentDisposition = $"attachment; filename=\"{downloadFileName}\"";

        return new Uri(_signer.GetPreSignedURL(request));
    }

    public void Dispose()
    {
        _client.Dispose();
        if (!ReferenceEquals(_signer, _client)) _signer.Dispose();
    }
}
